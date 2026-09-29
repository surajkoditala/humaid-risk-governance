-- Dev-only convenience: lets the frontend simulate "acting as" a given seeded user/role since
-- there's no real Auth0 login wired up yet (see DevBypassAuthHandler.cs). Not meant to survive
-- real auth being wired in - a real deployment derives identity from the access token, not a
-- public user-listing endpoint.
--
-- A user with no role grants at all is excluded (inner join) - same "not provisioned" treatment as
-- func_getUserByAuth0Subject/func_getUserById below.
CREATE OR REPLACE FUNCTION func_getAllUsers()
RETURNS TABLE (id UUID, display_name TEXT, email TEXT, roles TEXT[]) AS $$
    SELECT u.id, u.display_name, u.email, array_agg(ur.role ORDER BY ur.role)
    FROM app_user u
    JOIN app_user_role ur ON ur.user_id = u.id
    WHERE u.is_active = true
    GROUP BY u.id, u.display_name, u.email
    ORDER BY u.display_name;
$$ LANGUAGE sql STABLE;
