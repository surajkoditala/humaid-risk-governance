-- DEF-002: lets a service validate that an actor id the caller supplied actually holds the role
-- an action requires (e.g. CastVoteAsync requires CommitteeMember), instead of trusting the id at
-- face value. Not a substitute for deriving identity from a validated token - see DevBypassAuthHandler.cs
-- and DEF-010 for why that isn't wired up in this pass.
--
-- A membership check against app_user_role, not "what is the role" - a user can hold more than
-- one (Epic 11 follow-up), so equality against a single returned role would wrongly reject an
-- actor who holds the required role alongside others.
CREATE OR REPLACE FUNCTION func_userHasRole(p_user_id UUID, p_role TEXT)
RETURNS BOOLEAN AS $$
    SELECT EXISTS (
        SELECT 1
        FROM app_user u
        JOIN app_user_role ur ON ur.user_id = u.id
        WHERE u.id = p_user_id
          AND u.is_active = true
          AND ur.role = p_role
    );
$$ LANGUAGE sql STABLE;
