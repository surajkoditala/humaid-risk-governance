CREATE OR REPLACE FUNCTION func_getVendorById(p_id UUID)
RETURNS TABLE (
    id UUID, vendor_name TEXT, vendor_risk_rating TEXT, vendor_jurisdiction TEXT,
    data_access_scope TEXT, certification_status TEXT, updated_risk_rating TEXT
) AS $$
    SELECT id, vendor_name, vendor_risk_rating, vendor_jurisdiction, data_access_scope, certification_status, updated_risk_rating
    FROM mock_systems.vendor_registry
    WHERE id = p_id;
$$ LANGUAGE sql;
