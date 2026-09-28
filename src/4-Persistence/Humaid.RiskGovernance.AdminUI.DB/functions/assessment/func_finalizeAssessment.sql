-- US-6.3: the completeness checks (no outstanding AI-drafted sections, etc.) run in
-- AssessmentService.Finalize BEFORE this is called, so this function only records the fact of
-- finalization - it does not re-validate readiness itself.
--
-- Deliberately does NOT move change_request to 'PendingCommittee' - US-8.1 treats "finalize" and
-- "route to committee" as two distinct analyst actions (see func_routeToCommittee.sql). Finalizing
-- only locks the assessment from further Product Owner edits (US-6.3 AC2); routing is what makes
-- it visible to the committee queue.
CREATE OR REPLACE FUNCTION func_finalizeAssessment(
    p_assessment_id UUID,
    p_actor_user_id UUID
) RETURNS VOID AS $$
DECLARE
    v_change_request_id UUID;
    v_active_category_count INT;
BEGIN
    SELECT change_request_id INTO v_change_request_id FROM assessment WHERE id = p_assessment_id;

    -- DEF-001: a DB-level backstop for the worst case of the readiness gate passing vacuously -
    -- zero mapped categories. The full readiness checks (narrative reviewed, policy relied upon,
    -- score calculated per category) run in AssessmentService.CheckReadinessAsync before this is
    -- called; this does not re-implement all of them, only the cheapest, highest-value one.
    SELECT count(*) INTO v_active_category_count
    FROM assessment_category_mapping WHERE assessment_id = p_assessment_id AND is_active;

    IF v_active_category_count = 0 THEN
        RAISE EXCEPTION 'Cannot finalize an assessment with no mapped risk categories.';
    END IF;

    UPDATE assessment SET status = 'Finalized', finalized_by_user_id = p_actor_user_id, finalized_at = now()
    WHERE id = p_assessment_id;

    INSERT INTO audit_event (change_request_id, assessment_id, entity_type, entity_id, action, actor_user_id, actor_label, after_value)
    VALUES (v_change_request_id, p_assessment_id, 'Assessment', p_assessment_id, 'Finalized', p_actor_user_id, 'human',
            jsonb_build_object('finalizedBy', p_actor_user_id));
END;
$$ LANGUAGE plpgsql;
