-- The analyst-facing inbox - "every submitted change request", not scoped to one submitter.
-- Mirrors func_getChangeRequestsForUser.sql minus the WHERE on submitted_by_user_id.
--
-- Grid standard (filters/sort/server-side paging): p_sort_by/p_sort_dir only ever select a
-- column from the fixed v_column mapping below - the caller's values are never concatenated
-- directly into SQL text, so building the ORDER BY dynamically here stays injection-safe.
CREATE OR REPLACE FUNCTION func_getAllChangeRequests(
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
    submitted_at TIMESTAMPTZ, days_elapsed INT, due_at TIMESTAMPTZ, sla_state TEXT, total_count BIGINT
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

    RETURN QUERY EXECUTE format(
        'SELECT c.id, c.request_number, c.change_type, c.title, c.status, c.submitted_at,
                EXTRACT(DAY FROM now() - c.submitted_at)::INT AS days_elapsed,
                CASE WHEN c.status = ''Decisioned'' THEN NULL ELSE o.due_at END AS due_at,
                CASE WHEN c.status = ''Decisioned'' THEN (CASE WHEN ms.e2e_met THEN ''Met'' WHEN ms.e2e_met = false THEN ''Missed'' END)
                     ELSE o.overall_state END AS sla_state,
                COUNT(*) OVER()::BIGINT AS total_count
         FROM change_request c
         LEFT JOIN fn_sla_open_status() o ON o.change_request_id = c.id
         LEFT JOIN change_request_sla ms ON ms.change_request_id = c.id
         WHERE ($1::TEXT IS NULL OR c.status = $1)
           AND ($2::TEXT IS NULL OR c.change_type = $2)
           AND ($3::TEXT IS NULL OR c.title ILIKE ''%%'' || $3 || ''%%'' OR c.request_number ILIKE ''%%'' || $3 || ''%%'')
         ORDER BY %s %s NULLS LAST, c.id
         LIMIT $4 OFFSET $5',
        v_column, v_direction
    ) USING p_status, p_change_type, p_search, v_page_size, (v_page - 1) * v_page_size;
END;
$$ LANGUAGE plpgsql STABLE;
