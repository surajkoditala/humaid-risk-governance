-- Epic 11: resolves the caller's app_user from the Auth0 'sub' claim of the validated access
-- token. The app_user_role rows are the single source of truth for the caller's roles, so a role
-- grant/revoke takes effect on the caller's next request - no token refresh. Inactive users, and
-- users with no role grants at all, resolve to nothing (treated as not provisioned).
CREATE OR REPLACE FUNCTION func_getUserByAuth0Subject(p_auth0_subject TEXT)
RETURNS TABLE (id UUID, display_name TEXT, email TEXT, roles TEXT[]) AS $$
    SELECT u.id, u.display_name, u.email, array_agg(ur.role ORDER BY ur.role)
    FROM app_user u
    JOIN app_user_role ur ON ur.user_id = u.id
    WHERE u.auth0_subject = p_auth0_subject
      AND u.is_active = true
    GROUP BY u.id, u.display_name, u.email;
$$ LANGUAGE sql STABLE;
