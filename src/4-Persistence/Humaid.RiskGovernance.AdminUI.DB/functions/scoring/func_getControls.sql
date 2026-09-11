CREATE OR REPLACE FUNCTION func_getControls(p_risk_category_id UUID)
RETURNS TABLE (id UUID, name TEXT, description TEXT) AS $$
    SELECT c.id, c.name, c.description FROM control c WHERE c.risk_category_id = p_risk_category_id;
$$ LANGUAGE sql STABLE;
