-- Admin user-management screen: deactivate/reactivate. A deactivated user's role grants stay in
-- app_user_role untouched - is_active is what every identity-resolution function already filters
-- on (func_getUserById/func_getUserByAuth0Subject), so reactivating restores exactly the same
-- roles without re-granting them.
CREATE OR REPLACE FUNCTION func_setUserActive(
    p_user_id UUID,
    p_is_active BOOLEAN,
    p_reason TEXT,
    p_actor_user_id UUID
) RETURNS VOID AS $$
DECLARE
    v_before BOOLEAN;
BEGIN
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'A reason is required to deactivate or reactivate a user';
    END IF;

    SELECT is_active INTO v_before FROM app_user WHERE id = p_user_id;
    IF v_before IS NULL THEN
        RAISE EXCEPTION 'User % not found', p_user_id;
    END IF;

    UPDATE app_user SET is_active = p_is_active WHERE id = p_user_id;

    INSERT INTO audit_event (entity_type, entity_id, action, actor_user_id, actor_label, before_value, after_value, reason)
    VALUES ('AppUser', p_user_id, CASE WHEN p_is_active THEN 'Reactivated' ELSE 'Deactivated' END,
            p_actor_user_id, 'human', jsonb_build_object('isActive', v_before), jsonb_build_object('isActive', p_is_active), p_reason);
END;
$$ LANGUAGE plpgsql;
