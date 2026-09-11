-- US-8.1 AC1: everything currently sitting in the committee's decision queue.
CREATE OR REPLACE FUNCTION func_getCommitteeQueue()
RETURNS TABLE (
    assessment_id UUID, change_request_id UUID, request_number TEXT,
    change_type TEXT, title TEXT, routed_at TIMESTAMPTZ
) AS $$
    SELECT a.id, c.id, c.request_number, c.change_type, c.title, a.finalized_at
    FROM change_request c
    JOIN assessment a ON a.change_request_id = c.id
    WHERE c.status = 'PendingCommittee'
    ORDER BY a.finalized_at;
$$ LANGUAGE sql STABLE;
