-- Epic 19 - default SLA configuration and backfill. Idempotent: re-applied on every startup.
--
-- Default: the overall (start-to-decision) target is 2 business days for every request type - the
-- service level the problem statement sets against the 15-20 business-day baseline the platform
-- exists to reduce (agreed on the 7 Oct 2026 sync-up; the 24 Sep defaults of 2 / 8 / 5 / 15 were
-- replaced). No per-stage targets are seeded - an Admin can add them in Configuration. Warning
-- threshold 80% of the target; time waiting on the Product Owner is not charged to the analyst stage.
-- Run after seed_dev_users.sql.
DO $$
DECLARE
    v_admin UUID;
    v_config UUID := gen_random_uuid();
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sla_config) THEN
        SELECT id INTO v_admin FROM app_user WHERE auth0_subject = 'seed|admin-1';
        IF v_admin IS NOT NULL THEN
            INSERT INTO sla_config (id, version_number, at_risk_threshold_pct, pause_on_clarification, created_by_user_id, reason)
            VALUES (v_config, 1, 80, true, v_admin, 'Initial default: 2 business days start to decision (7 Oct 2026 sync-up)');

            INSERT INTO sla_target (sla_config_id, change_type, stage, target_business_days)
            SELECT v_config, ct.change_type, 'EndToEnd', 2
            FROM (VALUES ('Product'), ('Feature'), ('Process'), ('Vendor'), ('Geography'), ('CustomerSegment')) AS ct(change_type);
        END IF;
    END IF;
END $$;

-- Backfill for requests that existed before this epic (the triggers only cover new ones): pin them to
-- the active version, open their current stage, and record the end-to-end result for decided ones.
-- Stage entry times for these old rows are APPROXIMATE - the history did not exist when they moved
-- through their stages - taken from the assessment's own timestamps, falling back to submission time.
INSERT INTO change_request_sla (change_request_id, sla_config_id)
SELECT cr.id, (SELECT id FROM sla_config WHERE is_active)
FROM change_request cr
WHERE NOT EXISTS (SELECT 1 FROM change_request_sla s WHERE s.change_request_id = cr.id);

INSERT INTO change_request_stage_history (change_request_id, stage, entered_at, target_business_days)
SELECT cr.id, cr.status,
       CASE cr.status
           WHEN 'InAssessment' THEN COALESCE(a.created_at, cr.submitted_at)
           WHEN 'PendingCommittee' THEN COALESCE(a.finalized_at, a.created_at, cr.submitted_at)
           ELSE cr.submitted_at
       END,
       t.target_business_days
FROM change_request cr
JOIN change_request_sla s ON s.change_request_id = cr.id
LEFT JOIN assessment a ON a.change_request_id = cr.id
LEFT JOIN sla_target t ON t.sla_config_id = s.sla_config_id AND t.change_type = cr.change_type AND t.stage = cr.status
WHERE cr.status IN ('Submitted','InAssessment','PendingCommittee')
  AND NOT EXISTS (SELECT 1 FROM change_request_stage_history h WHERE h.change_request_id = cr.id);

UPDATE change_request_sla s
SET decided_at = q.q_decided,
    e2e_actual_business_days = q.q_days,
    e2e_met = q.q_met
FROM (
    SELECT cr.id AS q_cr, d.decided_at AS q_decided,
           GREATEST(fn_sla_business_days_between(cr.submitted_at, d.decided_at) - w.w_days, 0) AS q_days,
           CASE WHEN t.target_business_days IS NULL THEN NULL
                ELSE d.decided_at <= fn_sla_add_business_days(cr.submitted_at, t.target_business_days + w.w_days) END AS q_met
    FROM change_request cr
    JOIN change_request_sla s2 ON s2.change_request_id = cr.id AND s2.decided_at IS NULL
    JOIN assessment a ON a.change_request_id = cr.id
    JOIN committee_decision d ON d.assessment_id = a.id
    LEFT JOIN sla_config c ON c.id = s2.sla_config_id
    LEFT JOIN sla_target t ON t.sla_config_id = s2.sla_config_id AND t.change_type = cr.change_type AND t.stage = 'EndToEnd'
    CROSS JOIN LATERAL (
        SELECT CASE WHEN COALESCE(c.pause_on_clarification, true)
                    THEN fn_sla_waiting_days(cr.id, cr.submitted_at, d.decided_at) ELSE 0 END AS w_days
    ) w
    WHERE cr.status = 'Decisioned'
) q
WHERE s.change_request_id = q.q_cr;
