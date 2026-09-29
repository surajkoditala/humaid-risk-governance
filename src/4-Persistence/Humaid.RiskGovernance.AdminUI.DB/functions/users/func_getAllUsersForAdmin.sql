-- Admin user-management screen: every user, active or not, with every role and the raw
-- auth0_subject (null if that person has never logged in yet) - unlike func_getAllUsers/
-- func_getUserById/func_getUserByAuth0Subject, which exist to resolve a caller's own identity and
-- so deliberately exclude anyone inactive or roleless.
CREATE OR REPLACE FUNCTION func_getAllUsersForAdmin()
RETURNS TABLE (
    id UUID, auth0_subject TEXT, email TEXT, display_name TEXT,
    roles TEXT[], is_active BOOLEAN, created_at TIMESTAMPTZ
) AS $$
    SELECT
        u.id, u.auth0_subject, u.email, u.display_name,
        coalesce(array_agg(ur.role ORDER BY ur.role) FILTER (WHERE ur.role IS NOT NULL), '{}'),
        u.is_active, u.created_at
    FROM app_user u
    LEFT JOIN app_user_role ur ON ur.user_id = u.id
    GROUP BY u.id, u.auth0_subject, u.email, u.display_name, u.is_active, u.created_at
    ORDER BY u.display_name;
$$ LANGUAGE sql STABLE;
