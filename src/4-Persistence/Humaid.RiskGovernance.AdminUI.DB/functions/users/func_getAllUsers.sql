-- Dev-only convenience: lets the frontend simulate "acting as" a given seeded user/role since
-- there's no real Auth0 login wired up yet (see DevBypassAuthHandler.cs). Not meant to survive
-- real auth being wired in - a real deployment derives identity from the access token, not a
-- public user-listing endpoint.
CREATE OR REPLACE FUNCTION func_getAllUsers()
RETURNS TABLE (id UUID, display_name TEXT, email TEXT, role TEXT) AS $$
    SELECT id, display_name, email, role
    FROM app_user
    WHERE is_active = true
    ORDER BY role, display_name;
$$ LANGUAGE sql STABLE;
