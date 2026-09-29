-- US-1.3: "all my requests with current status and days elapsed since submission."
-- DEF-022: status alone only ever says "Decisioned" - the Product Owner never saw the actual
-- outcome or its conditions (US-8.3 AC3). The committee's resolution lives in committee_decision,
-- not on change_request itself (see func_recordCommitteeDecision.sql), so it's left-joined in here
-- rather than the requester's list making one extra round trip per row.
CREATE OR REPLACE FUNCTION func_getChangeRequestsForUser(p_user_id UUID)
RETURNS TABLE (
    id UUID, request_number TEXT, change_type TEXT, title TEXT, status TEXT,
    submitted_at TIMESTAMPTZ, days_elapsed INT, decision_resolution TEXT, decision_conditions_text TEXT
) AS $$
    SELECT c.id, c.request_number, c.change_type, c.title, c.status, c.submitted_at,
           EXTRACT(DAY FROM now() - c.submitted_at)::INT AS days_elapsed,
           d.resolution, d.conditions_text
    FROM change_request c
    LEFT JOIN assessment a ON a.change_request_id = c.id
    LEFT JOIN committee_decision d ON d.assessment_id = a.id
    WHERE c.submitted_by_user_id = p_user_id
    ORDER BY c.submitted_at DESC;
$$ LANGUAGE sql STABLE;
