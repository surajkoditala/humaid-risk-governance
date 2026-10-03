-- Epic 11: resolves an app_user by its own id. Used only by the local-development "acting as"
-- identity (DevBypassAuthHandler), where the caller names a seeded user directly instead of
-- presenting an Auth0 token. Inactive users, and users with no role grants at all, resolve to
-- nothing.
CREATE OR REPLACE FUNCTION func_getUserById(p_id UUID)
RETURNS TABLE (id UUID, display_name TEXT, email TEXT, roles TEXT[]) AS $$
    SELECT u.id, u.display_name, u.email, array_agg(ur.role ORDER BY ur.role)
    FROM app_user u
    JOIN app_user_role ur ON ur.user_id = u.id
    WHERE u.id = p_id
      AND u.is_active = true
    GROUP BY u.id, u.display_name, u.email;
$$ LANGUAGE sql STABLE;
