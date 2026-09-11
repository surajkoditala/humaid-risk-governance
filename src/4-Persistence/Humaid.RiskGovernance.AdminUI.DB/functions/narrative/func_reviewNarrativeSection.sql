-- US-6.3: analyst accepts an AI-drafted section as-is (no text change, so no reason required -
-- accepting isn't an edit). Compare func_editNarrativeSection.sql for the edit path.
CREATE OR REPLACE FUNCTION func_reviewNarrativeSection(
    p_assessment_id UUID,
    p_risk_category_id UUID,
    p_actor_user_id UUID
) RETURNS UUID AS $$
DECLARE
    v_id UUID;
BEGIN
    UPDATE assessment_narrative_section
    SET status = 'AnalystReviewed', updated_by_user_id = p_actor_user_id, updated_at = now()
    WHERE assessment_id = p_assessment_id AND risk_category_id = p_risk_category_id
    RETURNING id INTO v_id;

    INSERT INTO audit_event (assessment_id, entity_type, entity_id, action, actor_user_id, actor_label, after_value)
    VALUES (p_assessment_id, 'NarrativeSection', v_id, 'AnalystReviewed', p_actor_user_id, 'human',
            jsonb_build_object('riskCategoryId', p_risk_category_id, 'status', 'AnalystReviewed'));

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;
