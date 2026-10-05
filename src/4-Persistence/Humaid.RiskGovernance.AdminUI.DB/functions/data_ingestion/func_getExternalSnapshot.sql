CREATE OR REPLACE FUNCTION func_getExternalSnapshot(p_change_request_id UUID)
RETURNS TABLE (
    id UUID,
    change_request_id UUID,
    mock_customer_id UUID,
    customer_risk_context_json JSONB,
    mock_product_id UUID,
    product_risk_context_json JSONB,
    mock_vendor_id UUID,
    vendor_risk_context_json JSONB,
    ingested_at TIMESTAMPTZ
) AS $$
    SELECT
        s.id, s.change_request_id,
        s.mock_customer_id, s.customer_risk_context,
        s.mock_product_id, s.product_risk_context,
        s.mock_vendor_id, s.vendor_risk_context,
        s.ingested_at
    FROM change_request_external_snapshot s
    WHERE s.change_request_id = p_change_request_id;
$$ LANGUAGE sql;
