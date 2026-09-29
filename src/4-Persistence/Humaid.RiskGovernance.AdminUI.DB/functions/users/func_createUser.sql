-- Admin user-management screen: creates an app_user row and its initial role grant(s) in one
-- transaction, so a user is never left with zero roles between the two inserts. auth0_subject
-- starts null - this person hasn't logged in yet (func_setUserAuth0Subject links it later).
CREATE OR REPLACE FUNCTION func_createUser(
    p_email TEXT,
    p_display_name TEXT,
    p_roles TEXT[],
    p_reason TEXT,
    p_actor_user_id UUID
) RETURNS UUID AS $$
DECLARE
    v_id UUID := gen_random_uuid();
    v_role TEXT;
BEGIN
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'A reason is required to create a user';
    END IF;
    IF p_roles IS NULL OR array_length(p_roles, 1) IS NULL THEN
        RAISE EXCEPTION 'A user must be created with at least one role';
    END IF;

    INSERT INTO app_user (id, auth0_subject, email, display_name)
    VALUES (v_id, NULL, p_email, p_display_name);

    FOREACH v_role IN ARRAY p_roles LOOP
        INSERT INTO app_user_role (user_id, role, granted_by_user_id, reason)
        VALUES (v_id, v_role, p_actor_user_id, p_reason);
    END LOOP;

    INSERT INTO audit_event (entity_type, entity_id, action, actor_user_id, actor_label, after_value, reason)
    VALUES ('AppUser', v_id, 'Created', p_actor_user_id, 'human',
            jsonb_build_object('email', p_email, 'displayName', p_display_name, 'roles', p_roles), p_reason);

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;
