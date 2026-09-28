-- DEF-002: lets a service validate that an actor id the caller supplied actually holds the role
-- an action requires (e.g. CastVoteAsync requires CommitteeMember), instead of trusting the id at
-- face value. Not a substitute for deriving identity from a validated token - see DevBypassAuthHandler.cs
-- and DEF-010 for why that isn't wired up in this pass.
CREATE OR REPLACE FUNCTION func_getUserRole(p_user_id UUID)
RETURNS TEXT AS $$
    SELECT role FROM app_user WHERE id = p_user_id AND is_active = true;
$$ LANGUAGE sql STABLE;
