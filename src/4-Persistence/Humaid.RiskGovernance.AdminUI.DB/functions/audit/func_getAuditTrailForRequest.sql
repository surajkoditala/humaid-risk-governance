-- US-9.1: full chronological history for one change_request, across every module that wrote an
-- audit_event against either the request itself or its assessment.
--
-- before_value_json/after_value_json (not before_value/after_value) so Dapper maps them onto
-- AuditEvent.BeforeValueJson/AfterValueJson - see func_getChangeRequestById.sql's comment.
CREATE OR REPLACE FUNCTION func_getAuditTrailForRequest(p_change_request_id UUID)
RETURNS TABLE (
    id UUID, entity_type TEXT, entity_id UUID, action TEXT,
    actor_user_id UUID, actor_name TEXT, actor_label TEXT,
    before_value_json JSONB, after_value_json JSONB, reason TEXT, created_at TIMESTAMPTZ
) AS $$
    SELECT e.id, e.entity_type, e.entity_id, e.action, e.actor_user_id,
           u.display_name, e.actor_label, e.before_value, e.after_value, e.reason, e.created_at
    FROM audit_event e
    LEFT JOIN app_user u ON u.id = e.actor_user_id
    LEFT JOIN assessment a ON a.change_request_id = p_change_request_id
    WHERE e.change_request_id = p_change_request_id OR e.assessment_id = a.id
    ORDER BY e.created_at ASC;
$$ LANGUAGE sql STABLE;
