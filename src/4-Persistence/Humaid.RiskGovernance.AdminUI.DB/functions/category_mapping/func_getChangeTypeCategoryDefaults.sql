-- The grounding lookup CategoryMappingAiClient sends to Claude alongside the request details, so
-- the AI proposes from a fixed, named list rather than inventing categories (US-2.1 AC1).
CREATE OR REPLACE FUNCTION func_getChangeTypeCategoryDefaults(p_change_type TEXT)
RETURNS TABLE (risk_category_id UUID, code TEXT, name TEXT, citation_section TEXT, weight TEXT) AS $$
    SELECT rc.id, rc.code, rc.name, rc.citation_section, m.weight
    FROM change_request_type_category_map m
    JOIN risk_category rc ON rc.id = m.risk_category_id
    WHERE m.change_type = p_change_type
    ORDER BY m.weight; -- 'Primary' sorts before 'Secondary'
$$ LANGUAGE sql STABLE;
