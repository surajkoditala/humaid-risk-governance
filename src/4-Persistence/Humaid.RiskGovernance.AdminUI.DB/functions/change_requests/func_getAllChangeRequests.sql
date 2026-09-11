-- The analyst-facing inbox - "every submitted change request", not scoped to one submitter.
-- Mirrors func_getChangeRequestsForUser.sql minus the WHERE.
CREATE OR REPLACE FUNCTION func_getAllChangeRequests()
RETURNS TABLE (
    id UUID, request_number TEXT, change_type TEXT, title TEXT, status TEXT,
    submitted_at TIMESTAMPTZ, days_elapsed INT
) AS $$
    SELECT c.id, c.request_number, c.change_type, c.title, c.status, c.submitted_at,
           EXTRACT(DAY FROM now() - c.submitted_at)::INT AS days_elapsed
    FROM change_request c
    ORDER BY c.submitted_at DESC;
$$ LANGUAGE sql STABLE;
