CREATE OR REPLACE FUNCTION func_createChangeRequest(
    p_change_type TEXT,
    p_title TEXT,
    p_description TEXT,
    p_type_specific_fields JSONB,
    p_submitted_by_user_id UUID
) RETURNS TABLE (id UUID, request_number TEXT, status TEXT, submitted_at TIMESTAMPTZ) AS $$
DECLARE
    v_id UUID := gen_random_uuid();
    v_request_number TEXT := 'CR-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('change_request_number_seq')::text, 5, '0');
BEGIN
    INSERT INTO change_request (id, request_number, change_type, title, description, type_specific_fields, submitted_by_user_id)
    VALUES (v_id, v_request_number, p_change_type, p_title, p_description, COALESCE(p_type_specific_fields, '{}'::jsonb), p_submitted_by_user_id);

    INSERT INTO audit_event (change_request_id, entity_type, entity_id, action, actor_user_id, actor_label, after_value)
    VALUES (v_id, 'ChangeRequest', v_id, 'Created', p_submitted_by_user_id, 'human',
            jsonb_build_object('changeType', p_change_type, 'title', p_title, 'status', 'Submitted'));

    RETURN QUERY SELECT c.id, c.request_number, c.status, c.submitted_at FROM change_request c WHERE c.id = v_id;
END;
$$ LANGUAGE plpgsql;
