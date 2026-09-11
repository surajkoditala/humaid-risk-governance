CREATE OR REPLACE FUNCTION func_updateChangeRequestStatus(
    p_change_request_id UUID,
    p_new_status TEXT,
    p_actor_user_id UUID
) RETURNS VOID AS $$
DECLARE
    v_old_status TEXT;
BEGIN
    SELECT status INTO v_old_status FROM change_request WHERE id = p_change_request_id;

    UPDATE change_request SET status = p_new_status WHERE id = p_change_request_id;

    INSERT INTO audit_event (change_request_id, entity_type, entity_id, action, actor_user_id, actor_label, before_value, after_value)
    VALUES (p_change_request_id, 'ChangeRequest', p_change_request_id, 'StatusChanged', p_actor_user_id,
            CASE WHEN p_actor_user_id IS NULL THEN 'system/AI' ELSE 'human' END,
            jsonb_build_object('status', v_old_status), jsonb_build_object('status', p_new_status));
END;
$$ LANGUAGE plpgsql;
