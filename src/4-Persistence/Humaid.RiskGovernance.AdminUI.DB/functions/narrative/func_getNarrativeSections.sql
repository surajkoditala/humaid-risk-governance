-- unsupported_claim_flags_json (not unsupported_claim_flags) so Dapper maps it onto
-- NarrativeSection.UnsupportedClaimFlagsJson - see func_getChangeRequestById.sql's comment.
CREATE OR REPLACE FUNCTION func_getNarrativeSections(p_assessment_id UUID)
RETURNS TABLE (
    id UUID, risk_category_id UUID, category_name TEXT, narrative_text TEXT,
    status TEXT, unsupported_claim_flags_json JSONB, updated_at TIMESTAMPTZ
) AS $$
    SELECT s.id, s.risk_category_id, rc.name, s.narrative_text, s.status, s.unsupported_claim_flags, s.updated_at
    FROM assessment_narrative_section s
    JOIN risk_category rc ON rc.id = s.risk_category_id
    WHERE s.assessment_id = p_assessment_id;
$$ LANGUAGE sql STABLE;
