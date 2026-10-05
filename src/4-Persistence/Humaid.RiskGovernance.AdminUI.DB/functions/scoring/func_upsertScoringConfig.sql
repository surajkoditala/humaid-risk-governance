-- US-10.1: config change is a new versioned row; rejects any value that would let residual risk
-- reach zero (also enforced by scoring_config's own CHECK - this RAISE gives the friendlier,
-- explicit error message the acceptance criteria calls for).
CREATE OR REPLACE FUNCTION func_upsertScoringConfig(
    p_risk_category_id UUID,
    p_max_mitigation_factor NUMERIC,
    p_reason TEXT,
    p_actor_user_id UUID
) RETURNS UUID AS $$
DECLARE
    v_id UUID := gen_random_uuid();
BEGIN
    IF p_max_mitigation_factor >= 1.0 OR p_max_mitigation_factor < 0 THEN
        RAISE EXCEPTION 'max_mitigation_factor must be in [0, 1.0) - a value of 1.0 or more would let residual risk reach zero';
    END IF;
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'A reason is required to change a scoring configuration';
    END IF;

    UPDATE scoring_config SET is_active = false WHERE risk_category_id = p_risk_category_id AND is_active = true;

    INSERT INTO scoring_config (id, risk_category_id, max_mitigation_factor, created_by_user_id, reason)
    VALUES (v_id, p_risk_category_id, p_max_mitigation_factor, p_actor_user_id, p_reason);

    INSERT INTO audit_event (entity_type, entity_id, action, actor_user_id, actor_label, after_value, reason)
    VALUES ('ScoringConfig', v_id, 'ConfigChanged', p_actor_user_id, 'human',
            jsonb_build_object('riskCategoryId', p_risk_category_id, 'maxMitigationFactor', p_max_mitigation_factor), p_reason);

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;
