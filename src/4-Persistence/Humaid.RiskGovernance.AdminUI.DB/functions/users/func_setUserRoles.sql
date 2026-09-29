-- Admin user-management screen: replaces a user's entire role set in one call (the UI presents
-- a fixed multi-select, not one grant/revoke click at a time) - removes whichever roles are no
-- longer selected, adds whichever are newly selected, and audits the before/after set together so
-- the change reads as one edit rather than N separate grant/revoke rows.
CREATE OR REPLACE FUNCTION func_setUserRoles(
    p_user_id UUID,
    p_roles TEXT[],
    p_reason TEXT,
    p_actor_user_id UUID
) RETURNS VOID AS $$
DECLARE
    v_before TEXT[];
    v_role TEXT;
BEGIN
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'A reason is required to change a user''s roles';
    END IF;
    IF p_roles IS NULL OR array_length(p_roles, 1) IS NULL THEN
        RAISE EXCEPTION 'A user must hold at least one role';
    END IF;

    SELECT array_agg(role ORDER BY role) INTO v_before FROM app_user_role WHERE user_id = p_user_id;

    DELETE FROM app_user_role WHERE user_id = p_user_id AND role NOT IN (SELECT unnest(p_roles));

    FOREACH v_role IN ARRAY p_roles LOOP
        INSERT INTO app_user_role (user_id, role, granted_by_user_id, reason)
        VALUES (p_user_id, v_role, p_actor_user_id, p_reason)
        ON CONFLICT (user_id, role) DO NOTHING;
    END LOOP;

    INSERT INTO audit_event (entity_type, entity_id, action, actor_user_id, actor_label, before_value, after_value, reason)
    VALUES ('AppUser', p_user_id, 'RolesChanged', p_actor_user_id, 'human',
            jsonb_build_object('roles', v_before), jsonb_build_object('roles', p_roles), p_reason);
END;
$$ LANGUAGE plpgsql;
