CREATE OR REPLACE FUNCTION func_requestClarification(
    p_change_request_id UUID,
    p_requested_by_user_id UUID,
    p_question TEXT
) RETURNS UUID AS $$
DECLARE
    v_id UUID := gen_random_uuid();
BEGIN
    INSERT INTO change_request_clarification (id, change_request_id, requested_by_user_id, question)
    VALUES (v_id, p_change_request_id, p_requested_by_user_id, p_question);

    INSERT INTO audit_event (change_request_id, entity_type, entity_id, action, actor_user_id, actor_label, after_value)
    VALUES (p_change_request_id, 'Clarification', v_id, 'Requested', p_requested_by_user_id, 'human',
            jsonb_build_object('question', p_question));

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;
