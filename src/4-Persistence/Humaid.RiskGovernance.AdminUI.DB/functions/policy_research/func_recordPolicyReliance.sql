-- US-3.2: mark a surfaced policy chunk relied-upon / not-relevant.
CREATE OR REPLACE FUNCTION func_recordPolicyReliance(
    p_assessment_id UUID,
    p_risk_category_id UUID,
    p_policy_chunk_id UUID,
    p_decision TEXT,
    p_decided_by_user_id UUID
) RETURNS UUID AS $$
DECLARE
    v_id UUID;
BEGIN
    INSERT INTO assessment_policy_reliance (assessment_id, risk_category_id, policy_chunk_id, decision, decided_by_user_id)
    VALUES (p_assessment_id, p_risk_category_id, p_policy_chunk_id, p_decision, p_decided_by_user_id)
    ON CONFLICT (assessment_id, policy_chunk_id)
        DO UPDATE SET decision = EXCLUDED.decision, decided_by_user_id = EXCLUDED.decided_by_user_id, decided_at = now()
    RETURNING id INTO v_id;

    INSERT INTO audit_event (assessment_id, entity_type, entity_id, action, actor_user_id, actor_label, after_value)
    VALUES (p_assessment_id, 'PolicyReliance', v_id, 'Decided', p_decided_by_user_id, 'human',
            jsonb_build_object('policyChunkId', p_policy_chunk_id, 'decision', p_decision));

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;
