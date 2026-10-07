-- Epic 19 / US-19.2: called by the change_request triggers (schema/015_sla.sql) on every status change.
--   p_old_status NULL  -> the request was just submitted: pin it to the active SLA version and open its
--                         first stage.
--   otherwise          -> close the open stage (freezing its charged duration and whether it met the
--                         SLA - never recomputed later) and either open the next stage or, on
--                         'Decisioned', record the end-to-end result.
-- This only RECORDS what happened. It never changes a status, blocks a transition or decides anything.
CREATE OR REPLACE FUNCTION fn_sla_record_transition(p_change_request_id UUID, p_old_status TEXT, p_new_status TEXT)
RETURNS VOID AS $$
DECLARE
    v_cr change_request%ROWTYPE;
    v_config_id UUID;
    v_pause BOOLEAN;
    v_open change_request_stage_history%ROWTYPE;
    v_waiting INT;
    v_charged INT;
    v_e2e_target INT;
BEGIN
    SELECT * INTO v_cr FROM change_request WHERE id = p_change_request_id;

    IF p_old_status IS NULL THEN
        INSERT INTO change_request_sla (change_request_id, sla_config_id)
        VALUES (p_change_request_id, (SELECT id FROM sla_config WHERE is_active))
        ON CONFLICT (change_request_id) DO NOTHING;
    END IF;

    SELECT s.sla_config_id, COALESCE(c.pause_on_clarification, true)
    INTO v_config_id, v_pause
    FROM change_request_sla s
    LEFT JOIN sla_config c ON c.id = s.sla_config_id
    WHERE s.change_request_id = p_change_request_id;
    v_pause := COALESCE(v_pause, true);

    -- Close the stage the request is leaving.
    SELECT * INTO v_open FROM change_request_stage_history
    WHERE change_request_id = p_change_request_id AND left_at IS NULL
    FOR UPDATE;
    IF FOUND THEN
        v_waiting := CASE WHEN v_pause THEN fn_sla_waiting_days(p_change_request_id, v_open.entered_at, now()) ELSE 0 END;
        v_charged := GREATEST(fn_sla_business_days_between(v_open.entered_at, now()) - v_waiting, 0);
        UPDATE change_request_stage_history
        SET left_at = now(),
            actual_business_days = v_charged,
            met_sla = CASE WHEN v_open.target_business_days IS NULL THEN NULL
                           ELSE now() <= fn_sla_add_business_days(v_open.entered_at, v_open.target_business_days + v_waiting) END
        WHERE id = v_open.id;
    END IF;

    IF p_new_status = 'Decisioned' THEN
        SELECT target_business_days INTO v_e2e_target FROM sla_target
        WHERE sla_config_id = v_config_id AND change_type = v_cr.change_type AND stage = 'EndToEnd';
        v_waiting := CASE WHEN v_pause THEN fn_sla_waiting_days(p_change_request_id, v_cr.submitted_at, now()) ELSE 0 END;
        v_charged := GREATEST(fn_sla_business_days_between(v_cr.submitted_at, now()) - v_waiting, 0);
        UPDATE change_request_sla
        SET decided_at = now(),
            e2e_actual_business_days = v_charged,
            e2e_met = CASE WHEN v_e2e_target IS NULL THEN NULL
                           ELSE now() <= fn_sla_add_business_days(v_cr.submitted_at, v_e2e_target + v_waiting) END
        WHERE change_request_id = p_change_request_id;
    ELSIF p_new_status IN ('Submitted','InAssessment','PendingCommittee') THEN
        INSERT INTO change_request_stage_history (change_request_id, stage, entered_at, target_business_days)
        VALUES (p_change_request_id, p_new_status, now(),
                (SELECT target_business_days FROM sla_target
                 WHERE sla_config_id = v_config_id AND change_type = v_cr.change_type AND stage = p_new_status));
    END IF;
END;
$$ LANGUAGE plpgsql;
