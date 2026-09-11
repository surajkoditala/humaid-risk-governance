CREATE OR REPLACE FUNCTION func_listProducts()
RETURNS TABLE (
    id UUID, product_name TEXT, product_type TEXT, features_json JSONB,
    product_geography TEXT, launch_change_type TEXT, go_live_flag BOOLEAN, risk_rating TEXT
) AS $$
    SELECT id, product_name, product_type, features_json, product_geography, launch_change_type, go_live_flag, risk_rating
    FROM mock_systems.core_banking_product
    ORDER BY product_name;
$$ LANGUAGE sql;
