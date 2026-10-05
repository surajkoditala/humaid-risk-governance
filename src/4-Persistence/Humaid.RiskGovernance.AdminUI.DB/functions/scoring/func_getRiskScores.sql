CREATE OR REPLACE FUNCTION func_getRiskScores(p_assessment_id UUID)
RETURNS TABLE (
    id UUID, risk_category_id UUID, category_name TEXT, inherent_rating NUMERIC,
    control_effectiveness NUMERIC, mitigation_factor_applied NUMERIC, residual_rating NUMERIC,
    is_override BOOLEAN, override_reason TEXT, scored_by TEXT, created_at TIMESTAMPTZ
) AS $$
    SELECT s.id, s.risk_category_id, rc.name, s.inherent_rating, s.control_effectiveness,
           s.mitigation_factor_applied, s.residual_rating, s.is_override, s.override_reason, s.scored_by, s.created_at
    FROM assessment_risk_score s
    JOIN risk_category rc ON rc.id = s.risk_category_id
    WHERE s.assessment_id = p_assessment_id;
$$ LANGUAGE sql STABLE;
