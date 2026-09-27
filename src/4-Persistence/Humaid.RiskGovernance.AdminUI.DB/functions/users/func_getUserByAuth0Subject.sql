-- Epic 11: resolves the caller's app_user from the Auth0 'sub' claim of the validated access
-- token. The app_user row is the single source of truth for the caller's role and identity, so
-- a role change or deactivation takes effect on the caller's next request - no token refresh.
-- Inactive users resolve to nothing (treated as not provisioned).
CREATE OR REPLACE FUNCTION func_getUserByAuth0Subject(p_auth0_subject TEXT)
RETURNS TABLE (id UUID, display_name TEXT, email TEXT, role TEXT) AS $$
    SELECT id, display_name, email, role
    FROM app_user
    WHERE auth0_subject = p_auth0_subject
      AND is_active = true;
$$ LANGUAGE sql STABLE;
