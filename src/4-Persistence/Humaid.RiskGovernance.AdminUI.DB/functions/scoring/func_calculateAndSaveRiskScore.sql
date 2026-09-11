-- US-7.1: Residual Risk = Inherent Risk - (Control Effectiveness x Mitigation Factor). Purely
-- deterministic - no LLM involved in the calculation itself. See schema/010_scoring.sql for why
-- this can never reach zero given the table's own constraints.
CREATE OR REPLACE FUNCTION func_calculateAndSaveRiskScore(
    p_assessment_id UUID,
    p_risk_category_id UUID,
    p_inherent_rating NUMERIC,
    p_control_ids_credited JSONB,
    p_control_effectiveness NUMERIC
) RETURNS TABLE (id UUID, residual_rating NUMERIC, mitigation_factor_applied NUMERIC) AS $$
DECLARE
    v_id UUID;
    v_mitigation_factor NUMERIC;
    v_residual NUMERIC;
BEGIN
    SELECT max_mitigation_factor INTO v_mitigation_factor
    FROM scoring_config WHERE risk_category_id = p_risk_category_id AND is_active = true;

    IF v_mitigation_factor IS NULL THEN
        RAISE EXCEPTION 'No active scoring configuration for risk category %', p_risk_category_id;
    END IF;

    v_residual := p_inherent_rating - (p_control_effectiveness * v_mitigation_factor);

    INSERT INTO assessment_risk_score (
        id, assessment_id, risk_category_id, inherent_rating, control_ids_credited,
        control_effectiveness, mitigation_factor_applied, residual_rating, is_override, scored_by
    ) VALUES (
        gen_random_uuid(), p_assessment_id, p_risk_category_id, p_inherent_rating, COALESCE(p_control_ids_credited, '[]'::jsonb),
        p_control_effectiveness, v_mitigation_factor, v_residual, false, 'System'
    )
    ON CONFLICT (assessment_id, risk_category_id) DO UPDATE SET
        inherent_rating = EXCLUDED.inherent_rating, control_ids_credited = EXCLUDED.control_ids_credited,
        control_effectiveness = EXCLUDED.control_effectiveness, mitigation_factor_applied = EXCLUDED.mitigation_factor_applied,
        residual_rating = EXCLUDED.residual_rating, is_override = false, override_reason = NULL,
        scored_by = 'System', created_at = now()
    RETURNING assessment_risk_score.id INTO v_id;

    INSERT INTO audit_event (assessment_id, entity_type, entity_id, action, actor_label, after_value)
    VALUES (p_assessment_id, 'RiskScore', v_id, 'Calculated', 'system/AI',
            jsonb_build_object('riskCategoryId', p_risk_category_id, 'inherent', p_inherent_rating, 'residual', v_residual));

    RETURN QUERY SELECT v_id, v_residual, v_mitigation_factor;
END;
$$ LANGUAGE plpgsql;
