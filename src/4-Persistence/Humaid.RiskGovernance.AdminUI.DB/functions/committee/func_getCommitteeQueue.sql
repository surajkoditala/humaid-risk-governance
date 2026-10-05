-- US-8.1 AC1: everything currently sitting in the committee's decision queue.
--
-- Grid standard (filters/sort/server-side paging): p_sort_by/p_sort_dir only ever select a
-- column from the fixed v_column mapping below - the caller's values are never concatenated
-- directly into SQL text, so building the ORDER BY dynamically here stays injection-safe. No
-- status filter - this queue is always WHERE status = 'PendingCommittee' by definition.
CREATE OR REPLACE FUNCTION func_getCommitteeQueue(
    p_change_type TEXT DEFAULT NULL,
    p_search TEXT DEFAULT NULL,
    p_sort_by TEXT DEFAULT NULL,
    p_sort_dir TEXT DEFAULT NULL,
    p_page INT DEFAULT 1,
    p_page_size INT DEFAULT 10
)
RETURNS TABLE (
    assessment_id UUID, change_request_id UUID, request_number TEXT,
    change_type TEXT, title TEXT, routed_at TIMESTAMPTZ, total_count BIGINT
) AS $$
DECLARE
    v_column TEXT := CASE p_sort_by
        WHEN 'requestNumber' THEN 'c.request_number'
        WHEN 'changeType' THEN 'c.change_type'
        WHEN 'title' THEN 'c.title'
        WHEN 'routedAt' THEN 'a.finalized_at'
        ELSE 'a.finalized_at'
    END;
    v_direction TEXT := CASE WHEN lower(p_sort_dir) = 'desc' THEN 'DESC' ELSE 'ASC' END;
    v_page INT := GREATEST(COALESCE(p_page, 1), 1);
    v_page_size INT := LEAST(GREATEST(COALESCE(p_page_size, 10), 1), 200);
BEGIN
    -- No sort picked yet (first load) - keep this function's original default: oldest-routed first.
    IF p_sort_by IS NULL THEN
        v_column := 'a.finalized_at';
        v_direction := 'ASC';
    END IF;

    RETURN QUERY EXECUTE format(
        'SELECT a.id, c.id, c.request_number, c.change_type, c.title, a.finalized_at,
                COUNT(*) OVER()::BIGINT AS total_count
         FROM change_request c
         JOIN assessment a ON a.change_request_id = c.id
         WHERE c.status = ''PendingCommittee''
           AND ($1::TEXT IS NULL OR c.change_type = $1)
           AND ($2::TEXT IS NULL OR c.title ILIKE ''%%'' || $2 || ''%%'' OR c.request_number ILIKE ''%%'' || $2 || ''%%'')
         ORDER BY %s %s NULLS LAST, c.id
         LIMIT $3 OFFSET $4',
        v_column, v_direction
    ) USING p_change_type, p_search, v_page_size, (v_page - 1) * v_page_size;
END;
$$ LANGUAGE plpgsql STABLE;
