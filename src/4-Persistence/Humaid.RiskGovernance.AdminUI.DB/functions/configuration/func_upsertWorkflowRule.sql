-- US-10.2: a rule change is a new versioned row (never an in-place update), so in-flight requests
-- keep following the rule that was active when they were submitted, unless explicitly re-queried
-- against the new one - same versioning pattern as scoring_config (schema/010_scoring.sql).
CREATE OR REPLACE FUNCTION func_upsertWorkflowRule(
    p_rule_key TEXT,
    p_rule_value JSONB,
    p_reason TEXT,
    p_actor_user_id UUID
) RETURNS UUID AS $$
DECLARE
    v_id UUID := gen_random_uuid();
BEGIN
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'A reason is required to change a workflow rule';
    END IF;

    UPDATE workflow_rule SET is_active = false WHERE rule_key = p_rule_key AND is_active = true;

    INSERT INTO workflow_rule (id, rule_key, rule_value, created_by_user_id, reason)
    VALUES (v_id, p_rule_key, p_rule_value, p_actor_user_id, p_reason);

    INSERT INTO audit_event (entity_type, entity_id, action, actor_user_id, actor_label, after_value, reason)
    VALUES ('WorkflowRule', v_id, 'ConfigChanged', p_actor_user_id, 'human',
            jsonb_build_object('ruleKey', p_rule_key, 'ruleValue', p_rule_value), p_reason);

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;
