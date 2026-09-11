-- Inbound side of the feedback loop (Phase 3 Step 5) - updated vendor risk rating pushed back
-- from a committee decision.
CREATE OR REPLACE FUNCTION func_updateVendorRiskRating(p_id UUID, p_updated_risk_rating TEXT)
RETURNS TABLE (id UUID) AS $$
    UPDATE mock_systems.vendor_registry
    SET updated_risk_rating = p_updated_risk_rating
    WHERE id = p_id
    RETURNING id;
$$ LANGUAGE sql;
