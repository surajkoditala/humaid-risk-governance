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
    -- DEF-016: use the config that was active when THIS assessment started
    -- (assessment.created_at), not whatever is active right now - US-10.1 AC1: "takes effect only
    -- for assessments started after the change... existing in-flight assessments are unaffected."
    -- scoring_config is versioned per category (func_upsertScoringConfig never updates a row in
    -- place, only flips is_active and inserts a new one), so "the version in force at time T" is
    -- simply the most recent row created at or before T.
    SELECT sc.max_mitigation_factor INTO v_mitigation_factor
    FROM scoring_config sc
    JOIN assessment a ON a.id = p_assessment_id
    WHERE sc.risk_category_id = p_risk_category_id AND sc.created_at <= a.created_at
    ORDER BY sc.created_at DESC
    LIMIT 1;

    IF v_mitigation_factor IS NULL THEN
        RAISE EXCEPTION 'No scoring configuration was active for risk category % when this assessment started', p_risk_category_id;
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
