-- Epic 11 follow-up: closes the chicken-and-egg gap where an Admin-created user (auth0_subject
-- still NULL) can't be linked until an Admin knows their real Auth0 subject - which nobody learns
-- until that person has logged in once and been refused every role-gated endpoint. Called only as
-- a fallback from AppUserClaimsTransformation when func_getUserByAuth0Subject finds nothing, using
-- the email Auth0's own /userinfo endpoint returned for that exact access token (never a
-- client-supplied value). Only ever claims a row not already linked to someone else - a row whose
-- auth0_subject is already set is left alone, so this can't hijack an existing, distinct login.
-- Case-insensitive: Auth0's stored email casing doesn't always match what an Admin typed at
-- creation time.
CREATE OR REPLACE FUNCTION func_linkUserAuth0ByEmail(p_email TEXT, p_auth0_subject TEXT)
RETURNS TABLE (id UUID, display_name TEXT, email TEXT, roles TEXT[]) AS $$
DECLARE
    v_user_id UUID;
BEGIN
    SELECT u.id INTO v_user_id
    FROM app_user u
    WHERE lower(u.email) = lower(p_email)
      AND u.auth0_subject IS NULL
      AND u.is_active = true;

    IF v_user_id IS NULL THEN
        RETURN;
    END IF;

    UPDATE app_user SET auth0_subject = p_auth0_subject WHERE id = v_user_id;

    INSERT INTO audit_event (entity_type, entity_id, action, actor_label, after_value, reason)
    VALUES ('AppUser', v_user_id, 'Auth0SubjectLinked', 'system',
            jsonb_build_object('auth0Subject', p_auth0_subject),
            'Auto-linked via verified email match on first login');

    RETURN QUERY
    SELECT u.id, u.display_name, u.email, array_agg(ur.role ORDER BY ur.role)
    FROM app_user u
    JOIN app_user_role ur ON ur.user_id = u.id
    WHERE u.id = v_user_id
    GROUP BY u.id, u.display_name, u.email;
END;
$$ LANGUAGE plpgsql;
