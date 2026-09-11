CREATE OR REPLACE FUNCTION func_getCommitteeVotes(p_assessment_id UUID)
RETURNS TABLE (
    id UUID, committee_member_user_id UUID, committee_member_name TEXT,
    vote TEXT, conditions_text TEXT, rationale TEXT, voted_at TIMESTAMPTZ
) AS $$
    SELECT v.id, v.committee_member_user_id, u.display_name, v.vote, v.conditions_text, v.rationale, v.voted_at
    FROM committee_vote v
    JOIN app_user u ON u.id = v.committee_member_user_id
    WHERE v.assessment_id = p_assessment_id
    ORDER BY v.voted_at;
$$ LANGUAGE sql STABLE;
