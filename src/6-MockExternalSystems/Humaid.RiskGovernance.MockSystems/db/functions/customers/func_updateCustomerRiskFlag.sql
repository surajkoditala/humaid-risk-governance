-- Inbound side of the feedback loop (Phase 3 Step 5). Returns the updated row's id, or no rows if
-- p_id didn't match anything - the caller (Program.cs) maps that to 404, same as before this was
-- moved into a function.
CREATE OR REPLACE FUNCTION func_updateCustomerRiskFlag(p_id UUID, p_risk_flag TEXT)
RETURNS TABLE (id UUID) AS $$
    UPDATE mock_systems.crm_customer
    SET risk_flag = p_risk_flag
    WHERE id = p_id
    RETURNING id;
$$ LANGUAGE sql;
