-- US-8.2: one row per member per assessment - votes are never aggregated into a single record
-- (AC5), each stays individually attributable. committee_vote's own CHECK constraints
-- (schema/011_committee.sql) already enforce conditions_text/rationale being present for the vote
-- types that require them, so this function doesn't need to re-validate that.
CREATE OR REPLACE FUNCTION func_castCommitteeVote(
    p_assessment_id UUID,
    p_committee_member_user_id UUID,
    p_vote TEXT,
    p_conditions_text TEXT,
    p_rationale TEXT
) RETURNS UUID AS $$
DECLARE
    v_id UUID;
    v_change_request_id UUID;
BEGIN
    SELECT change_request_id INTO v_change_request_id FROM assessment WHERE id = p_assessment_id;

    INSERT INTO committee_vote (assessment_id, committee_member_user_id, vote, conditions_text, rationale)
    VALUES (p_assessment_id, p_committee_member_user_id, p_vote, p_conditions_text, p_rationale)
    ON CONFLICT (assessment_id, committee_member_user_id) DO UPDATE SET
        vote = EXCLUDED.vote, conditions_text = EXCLUDED.conditions_text, rationale = EXCLUDED.rationale, voted_at = now()
    RETURNING id INTO v_id;

    INSERT INTO audit_event (change_request_id, assessment_id, entity_type, entity_id, action, actor_user_id, actor_label, after_value)
    VALUES (v_change_request_id, p_assessment_id, 'CommitteeVote', v_id, 'Voted', p_committee_member_user_id, 'human',
            jsonb_build_object('vote', p_vote, 'conditionsText', p_conditions_text, 'rationale', p_rationale));

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;
