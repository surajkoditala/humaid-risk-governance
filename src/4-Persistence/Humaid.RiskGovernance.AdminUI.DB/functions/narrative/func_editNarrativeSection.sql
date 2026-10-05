-- US-6.1: any edit to AI-generated narrative text requires a reason; original stays in
-- audit_event.before_value.
CREATE OR REPLACE FUNCTION func_editNarrativeSection(
    p_assessment_id UUID,
    p_risk_category_id UUID,
    p_new_text TEXT,
    p_reason TEXT,
    p_actor_user_id UUID
) RETURNS UUID AS $$
DECLARE
    v_id UUID;
    v_before JSONB;
BEGIN
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'A reason is required to edit an AI-drafted narrative section';
    END IF;

    SELECT to_jsonb(s) INTO v_before FROM assessment_narrative_section s
        WHERE assessment_id = p_assessment_id AND risk_category_id = p_risk_category_id;

    UPDATE assessment_narrative_section
    SET narrative_text = p_new_text, status = 'AnalystEdited', updated_by_user_id = p_actor_user_id, updated_at = now()
    WHERE assessment_id = p_assessment_id AND risk_category_id = p_risk_category_id
    RETURNING id INTO v_id;

    INSERT INTO audit_event (assessment_id, entity_type, entity_id, action, actor_user_id, actor_label, before_value, after_value, reason)
    VALUES (p_assessment_id, 'NarrativeSection', v_id, 'AnalystEdited', p_actor_user_id, 'human',
            v_before, jsonb_build_object('riskCategoryId', p_risk_category_id, 'text', p_new_text), p_reason);

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;
