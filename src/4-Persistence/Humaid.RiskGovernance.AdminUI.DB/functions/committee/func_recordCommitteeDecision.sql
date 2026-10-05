-- US-8.3: the resolution itself (majority/unanimous/quorum rule) is computed in
-- CommitteeService.cs, reading the "CommitteeQuorum" workflow_rule (Epic 10 tie-in) - this
-- function only persists the already-decided outcome and updates the request's broad status.
--
-- change_request.status moves to 'Decisioned' (not the specific resolution value) to stay inside
-- the four broad statuses Epic 1 tracks (US-1.1); the specific resolution + any conditions live in
-- committee_decision, read via func_getCommitteeDecision.
CREATE OR REPLACE FUNCTION func_recordCommitteeDecision(
    p_assessment_id UUID,
    p_resolution TEXT,
    p_conditions_text TEXT
) RETURNS UUID AS $$
DECLARE
    v_id UUID := gen_random_uuid();
    v_change_request_id UUID;
BEGIN
    SELECT change_request_id INTO v_change_request_id FROM assessment WHERE id = p_assessment_id;

    INSERT INTO committee_decision (id, assessment_id, resolution, conditions_text)
    VALUES (v_id, p_assessment_id, p_resolution, p_conditions_text);

    UPDATE change_request SET status = 'Decisioned' WHERE id = v_change_request_id;

    INSERT INTO audit_event (change_request_id, assessment_id, entity_type, entity_id, action, actor_label, after_value)
    VALUES (v_change_request_id, p_assessment_id, 'CommitteeDecision', v_id, 'Decisioned', 'system/AI',
            jsonb_build_object('resolution', p_resolution, 'conditionsText', p_conditions_text));

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;
