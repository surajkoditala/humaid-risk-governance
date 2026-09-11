-- US-2.2: add/remove a category mapping; reason mandatory, original AI proposal never overwritten
-- (it stays in audit_event's before_value).
CREATE OR REPLACE FUNCTION func_overrideCategoryMapping(
    p_assessment_id UUID,
    p_risk_category_id UUID,
    p_is_active BOOLEAN, -- true = add, false = remove
    p_reason TEXT,
    p_actor_user_id UUID
) RETURNS UUID AS $$
DECLARE
    v_id UUID;
    v_before JSONB;
BEGIN
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'A reason is required to override a category mapping';
    END IF;

    SELECT to_jsonb(m) INTO v_before FROM assessment_category_mapping m
        WHERE assessment_id = p_assessment_id AND risk_category_id = p_risk_category_id;

    INSERT INTO assessment_category_mapping (assessment_id, risk_category_id, source, is_active, created_by_user_id)
    VALUES (p_assessment_id, p_risk_category_id, 'AnalystAdded', p_is_active, p_actor_user_id)
    ON CONFLICT (assessment_id, risk_category_id)
        DO UPDATE SET is_active = p_is_active, created_by_user_id = p_actor_user_id
    RETURNING id INTO v_id;

    INSERT INTO audit_event (assessment_id, entity_type, entity_id, action, actor_user_id, actor_label, before_value, after_value, reason)
    VALUES (p_assessment_id, 'CategoryMapping', v_id, 'Overridden', p_actor_user_id, 'human',
            v_before, jsonb_build_object('riskCategoryId', p_risk_category_id, 'isActive', p_is_active), p_reason);

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;
