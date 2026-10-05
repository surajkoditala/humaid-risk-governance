-- Needed by the frontend's "add a category" control (US-2.2) - an analyst can add any framework
-- category, not just the ones func_getChangeTypeCategoryDefaults would have suggested.
CREATE OR REPLACE FUNCTION func_getAllRiskCategories()
RETURNS TABLE (id UUID, code TEXT, name TEXT, citation_section TEXT) AS $$
    SELECT id, code, name, citation_section FROM risk_category ORDER BY name;
$$ LANGUAGE sql STABLE;
