-- Used by AssessmentService.Finalize to enforce US-3.2 AC2: at least one reviewed policy per
-- mapped risk category before finalization is allowed.
CREATE OR REPLACE FUNCTION func_getPolicyReliance(p_assessment_id UUID)
RETURNS TABLE (
    id UUID, risk_category_id UUID, policy_chunk_id UUID, decision TEXT, decided_at TIMESTAMPTZ,
    section_ref TEXT, chunk_text TEXT
) AS $$
    SELECT r.id, r.risk_category_id, r.policy_chunk_id, r.decision, r.decided_at, pc.section_ref, pc.chunk_text
    FROM assessment_policy_reliance r
    JOIN policy_chunk pc ON pc.id = r.policy_chunk_id
    WHERE r.assessment_id = p_assessment_id;
$$ LANGUAGE sql STABLE;
