CREATE OR REPLACE FUNCTION func_saveExternalSnapshot(
    p_change_request_id UUID,
    p_mock_customer_id UUID,
    p_customer_risk_context JSONB,
    p_mock_product_id UUID,
    p_product_risk_context JSONB,
    p_mock_vendor_id UUID,
    p_vendor_risk_context JSONB
) RETURNS TABLE (id UUID, ingested_at TIMESTAMPTZ) AS $$
BEGIN
    INSERT INTO change_request_external_snapshot (
        change_request_id, mock_customer_id, customer_risk_context,
        mock_product_id, product_risk_context, mock_vendor_id, vendor_risk_context
    ) VALUES (
        p_change_request_id, p_mock_customer_id, p_customer_risk_context,
        p_mock_product_id, p_product_risk_context, p_mock_vendor_id, p_vendor_risk_context
    )
    ON CONFLICT (change_request_id) DO NOTHING; -- immutable: never overwrite an existing snapshot

    INSERT INTO audit_event (change_request_id, entity_type, entity_id, action, actor_label, after_value)
    VALUES (p_change_request_id, 'ExternalSnapshot', p_change_request_id, 'Ingested', 'system',
            jsonb_build_object(
                'hasCustomer', p_mock_customer_id IS NOT NULL,
                'hasProduct', p_mock_product_id IS NOT NULL,
                'hasVendor', p_mock_vendor_id IS NOT NULL));

    RETURN QUERY SELECT s.id, s.ingested_at FROM change_request_external_snapshot s WHERE s.change_request_id = p_change_request_id;
END;
$$ LANGUAGE plpgsql;
