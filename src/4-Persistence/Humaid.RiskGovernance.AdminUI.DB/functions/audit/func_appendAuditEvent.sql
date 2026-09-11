-- Generic append, used directly by Services.Audit for events not already covered by a
-- domain-specific function above (e.g. AssessmentService cross-cutting events).
CREATE OR REPLACE FUNCTION func_appendAuditEvent(
    p_change_request_id UUID,
    p_assessment_id UUID,
    p_entity_type TEXT,
    p_entity_id UUID,
    p_action TEXT,
    p_actor_user_id UUID,
    p_actor_label TEXT,
    p_before_value JSONB,
    p_after_value JSONB,
    p_reason TEXT
) RETURNS UUID AS $$
DECLARE
    v_id UUID := gen_random_uuid();
BEGIN
    INSERT INTO audit_event (id, change_request_id, assessment_id, entity_type, entity_id, action, actor_user_id, actor_label, before_value, after_value, reason)
    VALUES (v_id, p_change_request_id, p_assessment_id, p_entity_type, p_entity_id, p_action, p_actor_user_id, COALESCE(p_actor_label, 'system/AI'), p_before_value, p_after_value, p_reason);
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;
