-- Epic 19 / US-19.1: save SLA configuration as a NEW version (the previous one is deactivated, never
-- overwritten - same pattern as func_upsertWorkflowRule / scoring_config), with a mandatory reason and
-- a ConfigChanged audit event carrying the before and after values.
--
-- p_targets is a JSON array of targets, each {"changeType", "stage", "targetBusinessDays"}:
--   [{"changeType":"Product","stage":"EndToEnd","targetBusinessDays":2},
--    {"changeType":"Product","stage":"InAssessment","targetBusinessDays":1}, ...]
-- The overall (EndToEnd, start-to-decision) target is REQUIRED for every change type - it is the
-- service level the business set (a decision in about 2 business days). Per-stage targets
-- (Submitted / InAssessment / PendingCommittee) are OPTIONAL: a stage with no target is still timed
-- and shown, it just has no target of its own to be late against.
-- Requests already in flight keep the version they were submitted under (change_request_sla pins it),
-- unless p_retroactive is true, in which case open requests are re-pinned to the new version and their
-- current stage target is refreshed (US-19.1 AC7). Finished stages are never touched.
CREATE OR REPLACE FUNCTION func_upsertSlaConfig(
    p_targets JSONB,
    p_at_risk_threshold_pct INT,
    p_pause_on_clarification BOOLEAN,
    p_retroactive BOOLEAN,
    p_reason TEXT,
    p_actor_user_id UUID
) RETURNS UUID AS $$
DECLARE
    v_id UUID := gen_random_uuid();
    v_version INT;
    v_entry JSONB;
    v_seen TEXT[] := ARRAY[]::TEXT[];
    v_key TEXT;
    v_type TEXT;
    v_days NUMERIC;
    v_before JSONB;
BEGIN
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'A reason is required to change the SLA configuration';
    END IF;
    IF p_at_risk_threshold_pct IS NULL OR p_at_risk_threshold_pct < 1 OR p_at_risk_threshold_pct > 99 THEN
        RAISE EXCEPTION 'The at-risk warning threshold must be a whole number between 1 and 99 (percent of the target)';
    END IF;
    IF p_targets IS NULL OR jsonb_typeof(p_targets) <> 'array' THEN
        RAISE EXCEPTION 'SLA targets must be a list of change type / stage targets';
    END IF;

    FOR v_entry IN SELECT * FROM jsonb_array_elements(p_targets) LOOP
        v_key := (v_entry->>'changeType') || '/' || (v_entry->>'stage');
        IF (v_entry->>'changeType') IS NULL OR (v_entry->>'changeType') NOT IN ('Product','Feature','Process','Vendor','Geography','CustomerSegment') THEN
            RAISE EXCEPTION 'Unknown change type in SLA targets: %', COALESCE(v_entry->>'changeType', '(blank)');
        END IF;
        IF (v_entry->>'stage') IS NULL OR (v_entry->>'stage') NOT IN ('Submitted','InAssessment','PendingCommittee','EndToEnd') THEN
            RAISE EXCEPTION 'Unknown stage in SLA targets: %', COALESCE(v_entry->>'stage', '(blank)');
        END IF;
        IF jsonb_typeof(v_entry->'targetBusinessDays') IS DISTINCT FROM 'number' THEN
            RAISE EXCEPTION 'The % target must be a whole number of business days greater than zero', v_key;
        END IF;
        v_days := (v_entry->>'targetBusinessDays')::NUMERIC;
        IF v_days <= 0 OR v_days <> trunc(v_days) THEN
            RAISE EXCEPTION 'The % target must be a whole number of business days greater than zero', v_key;
        END IF;
        IF v_key = ANY (v_seen) THEN
            RAISE EXCEPTION 'The % target was given more than once', v_key;
        END IF;
        v_seen := v_seen || v_key;
    END LOOP;

    FOREACH v_type IN ARRAY ARRAY['Product','Feature','Process','Vendor','Geography','CustomerSegment'] LOOP
        IF NOT ((v_type || '/EndToEnd') = ANY (v_seen)) THEN
            RAISE EXCEPTION 'An overall (start to decision) target is required for %', v_type;
        END IF;
    END LOOP;

    SELECT jsonb_build_object(
               'version', c.version_number,
               'atRiskThresholdPct', c.at_risk_threshold_pct,
               'pauseOnClarification', c.pause_on_clarification,
               'targets', (SELECT jsonb_agg(jsonb_build_object('changeType', t.change_type, 'stage', t.stage, 'targetBusinessDays', t.target_business_days)
                                            ORDER BY t.change_type, t.stage)
                           FROM sla_target t WHERE t.sla_config_id = c.id))
    INTO v_before
    FROM sla_config c WHERE c.is_active;

    SELECT COALESCE(MAX(version_number), 0) + 1 INTO v_version FROM sla_config;
    UPDATE sla_config SET is_active = false WHERE is_active;

    INSERT INTO sla_config (id, version_number, at_risk_threshold_pct, pause_on_clarification, created_by_user_id, reason)
    VALUES (v_id, v_version, p_at_risk_threshold_pct, COALESCE(p_pause_on_clarification, true), p_actor_user_id, p_reason);

    INSERT INTO sla_target (sla_config_id, change_type, stage, target_business_days)
    SELECT v_id, e->>'changeType', e->>'stage', (e->>'targetBusinessDays')::INT
    FROM jsonb_array_elements(p_targets) e;

    IF COALESCE(p_retroactive, false) THEN
        UPDATE change_request_sla s SET sla_config_id = v_id
        FROM change_request cr
        WHERE cr.id = s.change_request_id AND cr.status <> 'Decisioned';

        -- A stage with no target in the new version ends up with no target (null), not its old one.
        UPDATE change_request_stage_history h
        SET target_business_days = (
            SELECT t.target_business_days
            FROM change_request cr
            JOIN sla_target t ON t.change_type = cr.change_type AND t.stage = h.stage
            WHERE cr.id = h.change_request_id AND t.sla_config_id = v_id)
        WHERE h.left_at IS NULL;
    END IF;

    INSERT INTO audit_event (entity_type, entity_id, action, actor_user_id, actor_label, before_value, after_value, reason)
    VALUES ('SlaConfig', v_id, 'ConfigChanged', p_actor_user_id, 'human', v_before,
            jsonb_build_object('version', v_version,
                               'atRiskThresholdPct', p_at_risk_threshold_pct,
                               'pauseOnClarification', COALESCE(p_pause_on_clarification, true),
                               'retroactive', COALESCE(p_retroactive, false),
                               'targets', p_targets),
            p_reason);

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;
