-- Epic 19 / US-19.2 AC2: the live SLA position of every request that is not yet decisioned - computed
-- at read time from recorded timestamps, so there is no job to keep running and nothing can drift.
-- One row per open request: its current stage (elapsed charged business days, target, due date, state)
-- and its end-to-end position. overall_state is the worse of the two.
--   elapsed = business days since entering the stage, minus days spent waiting on the Product Owner
--             (when the pinned config pauses for clarifications)
--   due     = entry + (target + waiting days) business days
CREATE OR REPLACE FUNCTION fn_sla_open_status()
RETURNS TABLE (
    change_request_id UUID, stage TEXT, entered_at TIMESTAMPTZ, target_days INT, waiting_days INT,
    elapsed_days INT, due_at TIMESTAMPTZ, stage_state TEXT,
    e2e_target_days INT, e2e_elapsed_days INT, e2e_due_at TIMESTAMPTZ, e2e_state TEXT, overall_state TEXT
) AS $$
BEGIN
    RETURN QUERY
    WITH base AS (
        SELECT cr.id AS b_cr, cr.submitted_at AS b_submitted, h.stage AS b_stage, h.entered_at AS b_entered,
               h.target_business_days AS b_target,
               COALESCE(cfg.pause_on_clarification, true) AS b_pause,
               COALESCE(cfg.at_risk_threshold_pct, 80) AS b_pct,
               e.target_business_days AS b_e2e_target
        FROM change_request cr
        JOIN change_request_stage_history h ON h.change_request_id = cr.id AND h.left_at IS NULL
        LEFT JOIN change_request_sla s ON s.change_request_id = cr.id
        LEFT JOIN sla_config cfg ON cfg.id = s.sla_config_id
        LEFT JOIN sla_target e ON e.sla_config_id = cfg.id AND e.change_type = cr.change_type AND e.stage = 'EndToEnd'
        WHERE cr.status <> 'Decisioned'
    ), waited AS (
        SELECT b.*,
               CASE WHEN b.b_pause THEN fn_sla_waiting_days(b.b_cr, b.b_entered, now()) ELSE 0 END AS w_stage,
               CASE WHEN b.b_pause THEN fn_sla_waiting_days(b.b_cr, b.b_submitted, now()) ELSE 0 END AS w_e2e
        FROM base b
    ), measured AS (
        SELECT w.*,
               GREATEST(fn_sla_business_days_between(w.b_entered, now()) - w.w_stage, 0) AS m_el_stage,
               GREATEST(fn_sla_business_days_between(w.b_submitted, now()) - w.w_e2e, 0) AS m_el_e2e,
               CASE WHEN w.b_target IS NULL THEN NULL ELSE fn_sla_add_business_days(w.b_entered, w.b_target + w.w_stage) END AS m_due_stage,
               CASE WHEN w.b_e2e_target IS NULL THEN NULL ELSE fn_sla_add_business_days(w.b_submitted, w.b_e2e_target + w.w_e2e) END AS m_due_e2e
        FROM waited w
    ), judged AS (
        SELECT m.*,
               fn_sla_state(now(), m.m_due_stage, m.m_el_stage, m.b_target, m.b_pct) AS j_stage_state,
               fn_sla_state(now(), m.m_due_e2e, m.m_el_e2e, m.b_e2e_target, m.b_pct) AS j_e2e_state
        FROM measured m
    )
    SELECT j.b_cr, j.b_stage, j.b_entered, j.b_target, j.w_stage, j.m_el_stage, j.m_due_stage, j.j_stage_state,
           j.b_e2e_target, j.m_el_e2e, j.m_due_e2e, j.j_e2e_state,
           CASE WHEN 'Breached' IN (j.j_stage_state, j.j_e2e_state) THEN 'Breached'
                WHEN 'AtRisk' IN (j.j_stage_state, j.j_e2e_state) THEN 'AtRisk'
                WHEN j.j_stage_state IS NULL AND j.j_e2e_state IS NULL THEN NULL
                ELSE 'OnTrack' END
    FROM judged j;
END;
$$ LANGUAGE plpgsql STABLE;
