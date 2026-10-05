-- Inbound side of the feedback loop (Phase 3 Step 5) - go-live flag + risk rating pushed back
-- from a committee decision.
CREATE OR REPLACE FUNCTION func_updateProductRiskRating(p_id UUID, p_go_live BOOLEAN, p_risk_rating TEXT)
RETURNS TABLE (id UUID) AS $$
    UPDATE mock_systems.core_banking_product
    SET go_live_flag = p_go_live, risk_rating = p_risk_rating
    WHERE id = p_id
    RETURNING id;
$$ LANGUAGE sql;
