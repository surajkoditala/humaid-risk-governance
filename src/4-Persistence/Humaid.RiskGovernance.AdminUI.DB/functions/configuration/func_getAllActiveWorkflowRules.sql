-- US-10.2 AC1: "current rules in plain, structured form" - the whole active set, not buried in code.
-- rule_value_json (not rule_value) so Dapper maps it onto WorkflowRule.RuleValueJson.
CREATE OR REPLACE FUNCTION func_getAllActiveWorkflowRules()
RETURNS TABLE (id UUID, rule_key TEXT, rule_value_json JSONB, is_active BOOLEAN, created_at TIMESTAMPTZ) AS $$
    SELECT id, rule_key, rule_value, is_active, created_at
    FROM workflow_rule WHERE is_active = true
    ORDER BY rule_key;
$$ LANGUAGE sql STABLE;
