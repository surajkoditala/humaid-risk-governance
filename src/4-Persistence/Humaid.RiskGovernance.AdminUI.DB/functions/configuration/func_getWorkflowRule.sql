-- rule_value_json (not rule_value) so Dapper maps it onto WorkflowRule.RuleValueJson - see
-- func_getChangeRequestById.sql's comment.
CREATE OR REPLACE FUNCTION func_getWorkflowRule(p_rule_key TEXT)
RETURNS TABLE (id UUID, rule_key TEXT, rule_value_json JSONB, is_active BOOLEAN, created_at TIMESTAMPTZ) AS $$
    SELECT id, rule_key, rule_value, is_active, created_at
    FROM workflow_rule WHERE rule_key = p_rule_key AND is_active = true;
$$ LANGUAGE sql STABLE;
