-- Admin user-management screen: links (or re-links) a real Auth0 login to a user row - the UI
-- form for what auth0-setup.md's step 4 previously required a raw SQL UPDATE for. app_user's own
-- UNIQUE constraint on auth0_subject rejects linking the same real login to two different rows.
CREATE OR REPLACE FUNCTION func_setUserAuth0Subject(
    p_user_id UUID,
    p_auth0_subject TEXT,
    p_reason TEXT,
    p_actor_user_id UUID
) RETURNS VOID AS $$
DECLARE
    v_before TEXT;
BEGIN
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'A reason is required to link an Auth0 login';
    END IF;
    IF p_auth0_subject IS NULL OR btrim(p_auth0_subject) = '' THEN
        RAISE EXCEPTION 'An Auth0 subject is required';
    END IF;

    SELECT auth0_subject INTO v_before FROM app_user WHERE id = p_user_id;

    UPDATE app_user SET auth0_subject = p_auth0_subject WHERE id = p_user_id;

    INSERT INTO audit_event (entity_type, entity_id, action, actor_user_id, actor_label, before_value, after_value, reason)
    VALUES ('AppUser', p_user_id, 'Auth0SubjectLinked', p_actor_user_id, 'human',
            jsonb_build_object('auth0Subject', v_before), jsonb_build_object('auth0Subject', p_auth0_subject), p_reason);
END;
$$ LANGUAGE plpgsql;
