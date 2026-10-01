-- analyst_reason is read live from audit_event (this mapping's most recent Overridden entry),
-- not duplicated onto assessment_category_mapping itself - the table's own comment is explicit
-- that reason history belongs in the audit trail, not in extra columns here.
CREATE OR REPLACE FUNCTION func_getCategoryMapping(p_assessment_id UUID)
RETURNS TABLE (
    id UUID, risk_category_id UUID, category_code TEXT, category_name TEXT, citation_section TEXT,
    source TEXT, ai_citation TEXT, is_active BOOLEAN, created_at TIMESTAMPTZ, analyst_reason TEXT
) AS $$
    SELECT m.id, m.risk_category_id, rc.code, rc.name, rc.citation_section, m.source, m.ai_citation, m.is_active, m.created_at,
           latest_reason.reason
    FROM assessment_category_mapping m
    JOIN risk_category rc ON rc.id = m.risk_category_id
    LEFT JOIN LATERAL (
        SELECT ae.reason
        FROM audit_event ae
        WHERE ae.entity_type = 'CategoryMapping' AND ae.entity_id = m.id AND ae.action = 'Overridden'
        ORDER BY ae.created_at DESC
        LIMIT 1
    ) latest_reason ON true
    WHERE m.assessment_id = p_assessment_id
    ORDER BY m.created_at;
$$ LANGUAGE sql STABLE;
