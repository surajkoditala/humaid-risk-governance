-- Epic 19 / US-19.1 AC1: the active SLA version's settings (targets come from func_getSlaTargets).
CREATE OR REPLACE FUNCTION func_getSlaConfig()
RETURNS TABLE (
    id UUID, version_number INT, at_risk_threshold_pct INT, pause_on_clarification BOOLEAN,
    reason TEXT, created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT c.id, c.version_number, c.at_risk_threshold_pct, c.pause_on_clarification, c.reason, c.created_at
    FROM sla_config c
    WHERE c.is_active;
END;
$$ LANGUAGE plpgsql STABLE;
