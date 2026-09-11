-- Used by NarrativeService (and anywhere else that only has an assessment_id) to resolve back to
-- its change_request_id - assessment_category_mapping/assessment_policy_reliance are keyed by
-- assessment_id, but extracted_field and the change request itself are keyed by change_request_id.
CREATE OR REPLACE FUNCTION func_getAssessmentById(p_assessment_id UUID)
RETURNS TABLE (
    id UUID, change_request_id UUID, status TEXT,
    finalized_by_user_id UUID, finalized_at TIMESTAMPTZ, created_at TIMESTAMPTZ
) AS $$
    SELECT a.id, a.change_request_id, a.status, a.finalized_by_user_id, a.finalized_at, a.created_at
    FROM assessment a WHERE a.id = p_assessment_id;
$$ LANGUAGE sql STABLE;
