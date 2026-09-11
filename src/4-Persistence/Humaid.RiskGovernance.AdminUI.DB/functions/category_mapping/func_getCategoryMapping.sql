CREATE OR REPLACE FUNCTION func_getCategoryMapping(p_assessment_id UUID)
RETURNS TABLE (
    id UUID, risk_category_id UUID, category_code TEXT, category_name TEXT, citation_section TEXT,
    source TEXT, ai_citation TEXT, is_active BOOLEAN, created_at TIMESTAMPTZ
) AS $$
    SELECT m.id, m.risk_category_id, rc.code, rc.name, rc.citation_section, m.source, m.ai_citation, m.is_active, m.created_at
    FROM assessment_category_mapping m
    JOIN risk_category rc ON rc.id = m.risk_category_id
    WHERE m.assessment_id = p_assessment_id
    ORDER BY m.created_at;
$$ LANGUAGE sql STABLE;
