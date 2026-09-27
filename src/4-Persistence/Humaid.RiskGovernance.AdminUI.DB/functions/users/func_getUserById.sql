-- Epic 11: resolves an app_user by its own id. Used only by the local-development "acting as"
-- identity (DevBypassAuthHandler), where the caller names a seeded user directly instead of
-- presenting an Auth0 token. Inactive users resolve to nothing.
CREATE OR REPLACE FUNCTION func_getUserById(p_id UUID)
RETURNS TABLE (id UUID, display_name TEXT, email TEXT, role TEXT) AS $$
    SELECT id, display_name, email, role
    FROM app_user
    WHERE id = p_id
      AND is_active = true;
$$ LANGUAGE sql STABLE;
