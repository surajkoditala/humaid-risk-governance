CREATE OR REPLACE FUNCTION func_getCustomerById(p_id UUID)
RETURNS TABLE (
    id UUID, customer_name TEXT, customer_type TEXT, customer_geography TEXT,
    segment_classification TEXT, kyc_status TEXT, risk_flag TEXT
) AS $$
    SELECT id, customer_name, customer_type, customer_geography, segment_classification, kyc_status, risk_flag
    FROM mock_systems.crm_customer
    WHERE id = p_id;
$$ LANGUAGE sql;
