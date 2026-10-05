-- Epic 19 / US-19.5 AC1: open requests with their SLA position, most urgent first - Breached (most
-- overdue first), then At risk (closest to the target first), then On track. Filterable by current
-- stage, change type and state. A request with no SLA target configured is returned with a null
-- overall_state and sorted last.
CREATE OR REPLACE FUNCTION func_getSlaView(
    p_stage TEXT DEFAULT NULL,
    p_change_type TEXT DEFAULT NULL,
    p_state TEXT DEFAULT NULL
)
RETURNS TABLE (
    change_request_id UUID, request_number TEXT, title TEXT, change_type TEXT, stage TEXT,
    entered_at TIMESTAMPTZ, target_days INT, elapsed_days INT, waiting_days INT, due_at TIMESTAMPTZ,
    stage_state TEXT, e2e_due_at TIMESTAMPTZ, e2e_state TEXT, overall_state TEXT, days_overdue INT
) AS $$
BEGIN
    RETURN QUERY
    SELECT v.v_cr, v.v_number, v.v_title, v.v_type, v.v_stage,
           v.v_entered, v.v_target, v.v_elapsed, v.v_waiting, v.v_due,
           v.v_stage_state, v.v_e2e_due, v.v_e2e_state, v.v_overall, v.v_overdue
    FROM (
        SELECT o.change_request_id AS v_cr, cr.request_number AS v_number, cr.title AS v_title,
               cr.change_type AS v_type, o.stage AS v_stage, o.entered_at AS v_entered,
               o.target_days AS v_target, o.elapsed_days AS v_elapsed, o.waiting_days AS v_waiting,
               o.due_at AS v_due, o.stage_state AS v_stage_state, o.e2e_due_at AS v_e2e_due,
               o.e2e_state AS v_e2e_state, o.overall_state AS v_overall,
               GREATEST(
                   CASE WHEN o.stage_state = 'Breached' THEN fn_sla_business_days_between(o.due_at, now()) ELSE 0 END,
                   CASE WHEN o.e2e_state = 'Breached' THEN fn_sla_business_days_between(o.e2e_due_at, now()) ELSE 0 END
               ) AS v_overdue,
               (o.elapsed_days::NUMERIC / NULLIF(o.target_days, 0)) AS v_ratio,
               cr.submitted_at AS v_submitted
        FROM fn_sla_open_status() o
        JOIN change_request cr ON cr.id = o.change_request_id
        WHERE (p_stage IS NULL OR o.stage = p_stage)
          AND (p_change_type IS NULL OR cr.change_type = p_change_type)
          AND (p_state IS NULL OR o.overall_state = p_state)
    ) v
    ORDER BY CASE v.v_overall WHEN 'Breached' THEN 0 WHEN 'AtRisk' THEN 1 WHEN 'OnTrack' THEN 2 ELSE 3 END,
             v.v_overdue DESC,
             v.v_ratio DESC NULLS LAST,
             v.v_submitted;
END;
$$ LANGUAGE plpgsql STABLE;
