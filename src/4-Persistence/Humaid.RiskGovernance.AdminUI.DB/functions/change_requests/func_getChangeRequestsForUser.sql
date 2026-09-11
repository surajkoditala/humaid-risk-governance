-- US-1.3: "all my requests with current status and days elapsed since submission."
CREATE OR REPLACE FUNCTION func_getChangeRequestsForUser(p_user_id UUID)
RETURNS TABLE (
    id UUID, request_number TEXT, change_type TEXT, title TEXT, status TEXT,
    submitted_at TIMESTAMPTZ, days_elapsed INT
) AS $$
    SELECT c.id, c.request_number, c.change_type, c.title, c.status, c.submitted_at,
           EXTRACT(DAY FROM now() - c.submitted_at)::INT AS days_elapsed
    FROM change_request c
    WHERE c.submitted_by_user_id = p_user_id
    ORDER BY c.submitted_at DESC;
$$ LANGUAGE sql STABLE;
