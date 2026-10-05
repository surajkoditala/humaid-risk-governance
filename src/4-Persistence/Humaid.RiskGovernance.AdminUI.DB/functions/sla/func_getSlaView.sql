-- Epic 19 / US-19.5 AC1: open requests with their SLA position, one page at a time. Default order is
-- most urgent first - Breached (most overdue first), then At risk (closest to the target first), then
-- On track; a request with no SLA target configured has a null overall_state and sorts last.
--
-- Grid standard (filters / sort / server-side paging): filter by current stage, change type, SLA state
-- and a free-text search of title / request number. p_sort_by only ever selects one of the fixed CASE
-- branches below - the caller's value is never concatenated into SQL text - so sorting stays
-- injection-safe. Search uses position(), not LIKE, so % and _ in what the user types are literal.
--
-- The signature changed from the first (unpaged) version of this function, which never shipped; the
-- DROP below removes that old overload so a call can never be ambiguous between the two.
DROP FUNCTION IF EXISTS func_getSlaView(TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION func_getSlaView(
    p_stage TEXT DEFAULT NULL,
    p_change_type TEXT DEFAULT NULL,
    p_state TEXT DEFAULT NULL,
    p_search TEXT DEFAULT NULL,
    p_sort_by TEXT DEFAULT NULL,
    p_sort_dir TEXT DEFAULT NULL,
    p_page INT DEFAULT 1,
    p_page_size INT DEFAULT 10
)
RETURNS TABLE (
    change_request_id UUID, request_number TEXT, title TEXT, change_type TEXT, stage TEXT,
    entered_at TIMESTAMPTZ, target_days INT, elapsed_days INT, waiting_days INT, due_at TIMESTAMPTZ,
    stage_state TEXT, e2e_due_at TIMESTAMPTZ, e2e_state TEXT, overall_state TEXT, days_overdue INT,
    total_count BIGINT
) AS $$
DECLARE
    v_key TEXT := COALESCE(NULLIF(p_sort_by, ''), 'urgency');
    v_asc BOOLEAN := lower(COALESCE(p_sort_dir, 'asc')) <> 'desc';
    v_page INT := GREATEST(COALESCE(p_page, 1), 1);
    v_size INT := LEAST(GREATEST(COALESCE(p_page_size, 10), 1), 200);
    v_search TEXT := lower(NULLIF(btrim(COALESCE(p_search, '')), ''));
BEGIN
    RETURN QUERY
    SELECT v.v_cr, v.v_number, v.v_title, v.v_type, v.v_stage,
           v.v_entered, v.v_target, v.v_elapsed, v.v_waiting, v.v_due,
           v.v_stage_state, v.v_e2e_due, v.v_e2e_state, v.v_overall, v.v_overdue, v.v_total
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
               CASE o.overall_state WHEN 'Breached' THEN 0 WHEN 'AtRisk' THEN 1 WHEN 'OnTrack' THEN 2 ELSE 3 END AS v_rank,
               CASE o.stage WHEN 'Submitted' THEN 0 WHEN 'InAssessment' THEN 1 ELSE 2 END AS v_stage_rank,
               cr.submitted_at AS v_submitted,
               COUNT(*) OVER()::BIGINT AS v_total
        FROM fn_sla_open_status() o
        JOIN change_request cr ON cr.id = o.change_request_id
        WHERE (p_stage IS NULL OR o.stage = p_stage)
          AND (p_change_type IS NULL OR cr.change_type = p_change_type)
          AND (p_state IS NULL OR o.overall_state = p_state)
          AND (v_search IS NULL
               OR position(v_search IN lower(cr.title)) > 0
               OR position(v_search IN lower(cr.request_number)) > 0)
    ) v
    ORDER BY CASE WHEN v_key = 'requestNumber' AND v_asc THEN v.v_number END ASC,
             CASE WHEN v_key = 'requestNumber' AND NOT v_asc THEN v.v_number END DESC,
             CASE WHEN v_key = 'title' AND v_asc THEN v.v_title END ASC,
             CASE WHEN v_key = 'title' AND NOT v_asc THEN v.v_title END DESC,
             CASE WHEN v_key = 'changeType' AND v_asc THEN v.v_type END ASC,
             CASE WHEN v_key = 'changeType' AND NOT v_asc THEN v.v_type END DESC,
             CASE WHEN v_key = 'stage' AND v_asc THEN v.v_stage_rank END ASC,
             CASE WHEN v_key = 'stage' AND NOT v_asc THEN v.v_stage_rank END DESC,
             CASE WHEN v_key = 'progress' AND v_asc THEN v.v_ratio END ASC NULLS LAST,
             CASE WHEN v_key = 'progress' AND NOT v_asc THEN v.v_ratio END DESC NULLS LAST,
             CASE WHEN v_key = 'dueAt' AND v_asc THEN v.v_due END ASC NULLS LAST,
             CASE WHEN v_key = 'dueAt' AND NOT v_asc THEN v.v_due END DESC NULLS LAST,
             CASE WHEN v_key = 'urgency' THEN v.v_rank END ASC,
             CASE WHEN v_key = 'urgency' THEN v.v_overdue END DESC,
             CASE WHEN v_key = 'urgency' THEN v.v_ratio END DESC NULLS LAST,
             v.v_submitted, v.v_cr
    LIMIT v_size OFFSET (v_page - 1) * v_size;
END;
$$ LANGUAGE plpgsql STABLE;
