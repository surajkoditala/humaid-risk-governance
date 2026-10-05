-- Epic 19 / US-19.2: one request's SLA picture, for the analyst workspace strip.
--   scope 'Stage'      the stage it is in now (live)
--   scope 'EndToEnd'   submission -> decision: live while open, 'Met'/'Missed' once decided
--   scope 'Completed'  a stage it has already left (frozen - never recomputed)
-- waiting_days is the time spent waiting on the Product Owner, shown separately so the analyst
-- stage is not charged for it (US-19.2 AC4).
CREATE OR REPLACE FUNCTION func_getRequestSla(p_change_request_id UUID)
RETURNS TABLE (
    scope TEXT, stage TEXT, entered_at TIMESTAMPTZ, left_at TIMESTAMPTZ, target_days INT,
    elapsed_days INT, waiting_days INT, due_at TIMESTAMPTZ, state TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 'Stage'::TEXT, o.stage, o.entered_at, NULL::TIMESTAMPTZ, o.target_days,
           o.elapsed_days, o.waiting_days, o.due_at, o.stage_state
    FROM fn_sla_open_status() o WHERE o.change_request_id = p_change_request_id
    UNION ALL
    SELECT 'EndToEnd'::TEXT, NULL::TEXT, cr.submitted_at, NULL::TIMESTAMPTZ, o.e2e_target_days,
           o.e2e_elapsed_days, NULL::INT, o.e2e_due_at, o.e2e_state
    FROM fn_sla_open_status() o JOIN change_request cr ON cr.id = o.change_request_id
    WHERE o.change_request_id = p_change_request_id
    UNION ALL
    SELECT 'EndToEnd'::TEXT, NULL::TEXT, cr.submitted_at, s.decided_at, t.target_business_days,
           s.e2e_actual_business_days, NULL::INT, NULL::TIMESTAMPTZ,
           CASE WHEN s.e2e_met THEN 'Met' WHEN s.e2e_met = false THEN 'Missed' END
    FROM change_request_sla s
    JOIN change_request cr ON cr.id = s.change_request_id
    LEFT JOIN sla_target t ON t.sla_config_id = s.sla_config_id AND t.change_type = cr.change_type AND t.stage = 'EndToEnd'
    WHERE s.change_request_id = p_change_request_id AND s.decided_at IS NOT NULL
    UNION ALL
    SELECT 'Completed'::TEXT, h.stage, h.entered_at, h.left_at, h.target_business_days,
           h.actual_business_days, NULL::INT, NULL::TIMESTAMPTZ,
           CASE WHEN h.met_sla THEN 'Met' WHEN h.met_sla = false THEN 'Missed' END
    FROM change_request_stage_history h
    WHERE h.change_request_id = p_change_request_id AND h.left_at IS NOT NULL;
END;
$$ LANGUAGE plpgsql STABLE;
