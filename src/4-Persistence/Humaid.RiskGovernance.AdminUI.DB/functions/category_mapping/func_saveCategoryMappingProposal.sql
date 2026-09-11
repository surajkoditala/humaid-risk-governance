-- US-2.1: called by the service layer after CategoryMappingAiClient (real Claude call) returns a
-- proposed category + citation. Actor is 'system/AI', not a user.
CREATE OR REPLACE FUNCTION func_saveCategoryMappingProposal(
    p_assessment_id UUID,
    p_risk_category_id UUID,
    p_ai_citation TEXT
) RETURNS UUID AS $$
DECLARE
    v_id UUID;
BEGIN
    INSERT INTO assessment_category_mapping (assessment_id, risk_category_id, source, ai_citation)
    VALUES (p_assessment_id, p_risk_category_id, 'AiProposed', p_ai_citation)
    ON CONFLICT (assessment_id, risk_category_id) DO UPDATE SET ai_citation = EXCLUDED.ai_citation
    RETURNING id INTO v_id;

    INSERT INTO audit_event (assessment_id, entity_type, entity_id, action, actor_label, after_value)
    VALUES (p_assessment_id, 'CategoryMapping', v_id, 'AiProposed', 'system/AI',
            jsonb_build_object('riskCategoryId', p_risk_category_id, 'citation', p_ai_citation));

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;
