-- US-7.2: reason mandatory; residual must stay > 0 even after an override (controls mitigate,
-- they never eliminate - the rule applies to analyst judgment too, not just the formula).
CREATE OR REPLACE FUNCTION func_overrideRiskScore(
    p_assessment_id UUID,
    p_risk_category_id UUID,
    p_new_residual_rating NUMERIC,
    p_reason TEXT,
    p_actor_user_id UUID
) RETURNS UUID AS $$
DECLARE
    v_id UUID;
    v_before JSONB;
BEGIN
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'A reason is required to override a risk score';
    END IF;
    IF p_new_residual_rating <= 0 THEN
        RAISE EXCEPTION 'residual_rating must be greater than zero - controls mitigate risk, they never eliminate it';
    END IF;

    SELECT to_jsonb(s) INTO v_before FROM assessment_risk_score s
        WHERE assessment_id = p_assessment_id AND risk_category_id = p_risk_category_id;

    UPDATE assessment_risk_score
    SET residual_rating = p_new_residual_rating, is_override = true, override_reason = p_reason
    WHERE assessment_id = p_assessment_id AND risk_category_id = p_risk_category_id
    RETURNING id INTO v_id;

    INSERT INTO audit_event (assessment_id, entity_type, entity_id, action, actor_user_id, actor_label, before_value, after_value, reason)
    VALUES (p_assessment_id, 'RiskScore', v_id, 'Overridden', p_actor_user_id, 'human',
            v_before, jsonb_build_object('riskCategoryId', p_risk_category_id, 'residual', p_new_residual_rating), p_reason);

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;
