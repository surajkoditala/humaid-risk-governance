-- Epic 19 / US-19.1 AC1: the active SLA version's target in business days for every change type and stage.
CREATE OR REPLACE FUNCTION func_getSlaTargets()
RETURNS TABLE (change_type TEXT, stage TEXT, target_business_days INT) AS $$
BEGIN
    RETURN QUERY
    SELECT t.change_type, t.stage, t.target_business_days
    FROM sla_target t
    JOIN sla_config c ON c.id = t.sla_config_id AND c.is_active
    ORDER BY t.change_type,
             CASE t.stage WHEN 'Submitted' THEN 0 WHEN 'InAssessment' THEN 1 WHEN 'PendingCommittee' THEN 2 ELSE 3 END;
END;
$$ LANGUAGE plpgsql STABLE;
