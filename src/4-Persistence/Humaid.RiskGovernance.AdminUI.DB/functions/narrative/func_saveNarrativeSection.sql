-- US-5.1/US-5.2: (re)draft one category's narrative. Used for both the first AI draft and a
-- "regenerate with feedback" call - both are the AI producing a new AiDrafted version; the prior
-- text is preserved in audit_event.before_value, never lost (US-5.2 AC2).
CREATE OR REPLACE FUNCTION func_saveNarrativeSection(
    p_assessment_id UUID,
    p_risk_category_id UUID,
    p_narrative_text TEXT,
    p_unsupported_claim_flags JSONB
) RETURNS UUID AS $$
DECLARE
    v_id UUID;
    v_before JSONB;
BEGIN
    SELECT to_jsonb(s) INTO v_before FROM assessment_narrative_section s
        WHERE assessment_id = p_assessment_id AND risk_category_id = p_risk_category_id;

    INSERT INTO assessment_narrative_section (assessment_id, risk_category_id, narrative_text, unsupported_claim_flags, status)
    VALUES (p_assessment_id, p_risk_category_id, p_narrative_text, COALESCE(p_unsupported_claim_flags, '[]'::jsonb), 'AiDrafted')
    ON CONFLICT (assessment_id, risk_category_id) DO UPDATE SET
        narrative_text = EXCLUDED.narrative_text, unsupported_claim_flags = EXCLUDED.unsupported_claim_flags,
        status = 'AiDrafted', updated_by_user_id = NULL, updated_at = now()
    RETURNING id INTO v_id;

    INSERT INTO audit_event (assessment_id, entity_type, entity_id, action, actor_label, before_value, after_value)
    VALUES (p_assessment_id, 'NarrativeSection', v_id, 'AiDrafted', 'system/AI',
            v_before, jsonb_build_object('riskCategoryId', p_risk_category_id, 'text', p_narrative_text));

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;
