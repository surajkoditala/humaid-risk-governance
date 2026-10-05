-- US-8.1: moves a Finalized assessment's change request into the committee queue. Distinct from
-- finalization itself (func_finalizeAssessment) - see that file's comment.
CREATE OR REPLACE FUNCTION func_routeToCommittee(
    p_assessment_id UUID,
    p_actor_user_id UUID
) RETURNS VOID AS $$
DECLARE
    v_change_request_id UUID;
    v_assessment_status TEXT;
BEGIN
    SELECT change_request_id, status INTO v_change_request_id, v_assessment_status
    FROM assessment WHERE id = p_assessment_id;

    IF v_assessment_status IS DISTINCT FROM 'Finalized' THEN
        RAISE EXCEPTION 'Assessment % must be Finalized before it can be routed to committee (current status: %)',
            p_assessment_id, v_assessment_status;
    END IF;

    UPDATE change_request SET status = 'PendingCommittee' WHERE id = v_change_request_id;

    INSERT INTO audit_event (change_request_id, assessment_id, entity_type, entity_id, action, actor_user_id, actor_label, after_value)
    VALUES (v_change_request_id, p_assessment_id, 'ChangeRequest', v_change_request_id, 'Routed', p_actor_user_id, 'human',
            jsonb_build_object('status', 'PendingCommittee'));
END;
$$ LANGUAGE plpgsql;
