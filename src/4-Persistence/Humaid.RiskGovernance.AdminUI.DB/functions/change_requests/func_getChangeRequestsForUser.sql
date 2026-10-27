-- US-1.3: "all my requests with current status and days elapsed since submission."
-- Epic 19 (US-19.5 AC4): also the due date and whether the request is on track - the requester sees
-- only that, never other requests or the internal SLA reporting.
-- DEF-022: status alone only ever says "Decisioned" - the Product Owner never saw the actual
-- outcome or its conditions (US-8.3 AC3). The committee's resolution lives in committee_decision,
-- not on change_request itself (see func_recordCommitteeDecision.sql), so it's left-joined in here
-- rather than the requester's list making one extra round trip per row.
--
-- Grid standard (filters/sort/server-side paging): p_sort_by/p_sort_dir only ever select a
-- column from the fixed v_column mapping below - the caller's values are never concatenated
-- directly into SQL text, so building the ORDER BY dynamically here stays injection-safe.
CREATE OR REPLACE FUNCTION func_getChangeRequestsForUser(
    p_user_id UUID,
    p_status TEXT DEFAULT NULL,
    p_change_type TEXT DEFAULT NULL,
    p_search TEXT DEFAULT NULL,
    p_sort_by TEXT DEFAULT NULL,
    p_sort_dir TEXT DEFAULT NULL,
    p_page INT DEFAULT 1,
    p_page_size INT DEFAULT 10
)
RETURNS TABLE (
    id UUID, request_number TEXT, change_type TEXT, title TEXT, status TEXT,
    submitted_at TIMESTAMPTZ, days_elapsed INT, decision_resolution TEXT, decision_conditions_text TEXT,
    due_at TIMESTAMPTZ, sla_state TEXT, total_count BIGINT
) AS $$
DECLARE
    v_column TEXT := CASE p_sort_by
        WHEN 'requestNumber' THEN 'c.request_number'
        WHEN 'changeType' THEN 'c.change_type'
        WHEN 'title' THEN 'c.title'
        WHEN 'status' THEN 'c.status'
        WHEN 'daysElapsed' THEN 'c.submitted_at'
        ELSE 'c.submitted_at'
    END;
    -- days_elapsed counts down as submitted_at counts up, so "largest days elapsed first" is
    -- submitted_at ASC, not DESC - flip the direction for that one column only.
    v_direction TEXT := CASE
        WHEN p_sort_by = 'daysElapsed' THEN (CASE WHEN lower(p_sort_dir) = 'asc' THEN 'DESC' ELSE 'ASC' END)
        ELSE (CASE WHEN lower(p_sort_dir) = 'desc' THEN 'DESC' ELSE 'ASC' END)
    END;
    v_page INT := GREATEST(COALESCE(p_page, 1), 1);
    v_page_size INT := LEAST(GREATEST(COALESCE(p_page_size, 10), 1), 200);
BEGIN
    -- No sort picked yet (first load) - keep this function's original default: newest first.
    IF p_sort_by IS NULL THEN
        v_column := 'c.submitted_at';
        v_direction := 'DESC';
    END IF;

    -- Epic 19: due_at is when the DECISION is due (the overall target) - what a requester or analyst wants to
    -- know; the current stage's own due date is only used when no overall target is set.
    RETURN QUERY EXECUTE format(
        'SELECT c.id, c.request_number, c.change_type, c.title, c.status, c.submitted_at,
                EXTRACT(DAY FROM now() - c.submitted_at)::INT AS days_elapsed,
                d.resolution, d.conditions_text,
                CASE WHEN c.status = ''Decisioned'' THEN NULL ELSE COALESCE(o.e2e_due_at, o.due_at) END AS due_at,
                CASE WHEN c.status = ''Decisioned'' THEN (CASE WHEN ms.e2e_met THEN ''Met'' WHEN ms.e2e_met = false THEN ''Missed'' END)
                     ELSE o.overall_state END AS sla_state,
                COUNT(*) OVER()::BIGINT AS total_count
         FROM change_request c
         LEFT JOIN assessment a ON a.change_request_id = c.id
         LEFT JOIN committee_decision d ON d.assessment_id = a.id
         LEFT JOIN fn_sla_open_status() o ON o.change_request_id = c.id
         LEFT JOIN change_request_sla ms ON ms.change_request_id = c.id
         WHERE c.submitted_by_user_id = $1
           AND ($2::TEXT IS NULL OR c.status = $2)
           AND ($3::TEXT IS NULL OR c.change_type = $3)
           AND ($4::TEXT IS NULL OR c.title ILIKE ''%%'' || $4 || ''%%'' OR c.request_number ILIKE ''%%'' || $4 || ''%%'')
         ORDER BY %s %s NULLS LAST, c.id
         LIMIT $5 OFFSET $6',
        v_column, v_direction
    ) USING p_user_id, p_status, p_change_type, p_search, v_page_size, (v_page - 1) * v_page_size;
END;
$$ LANGUAGE plpgsql STABLE;
