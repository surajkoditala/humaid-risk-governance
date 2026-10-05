CREATE OR REPLACE FUNCTION func_getAssessmentByChangeRequest(p_change_request_id UUID)
RETURNS TABLE (
    id UUID, change_request_id UUID, status TEXT,
    finalized_by_user_id UUID, finalized_at TIMESTAMPTZ, created_at TIMESTAMPTZ
) AS $$
    SELECT a.id, a.change_request_id, a.status, a.finalized_by_user_id, a.finalized_at, a.created_at
    FROM assessment a WHERE a.change_request_id = p_change_request_id;
$$ LANGUAGE sql STABLE;
