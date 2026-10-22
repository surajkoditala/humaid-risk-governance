--
-- PostgreSQL database dump
--

\restrict xeS8sDMl5gIZ5eGmceey9gNe58JwrrSUn3oSKu7Xe23RcfklTqVYzJwxs0WuTLM

-- Dumped from database version 17.11
-- Dumped by pg_dump version 18.4

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: mock_systems; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA mock_systems;


--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

-- *not* creating schema, since initdb creates it


--
-- Name: fn_block_audit_event_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_block_audit_event_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    RAISE EXCEPTION 'audit_event is append-only: % is not permitted', TG_OP;
END;
$$;


--
-- Name: fn_sla_add_business_days(timestamp with time zone, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_sla_add_business_days(p_start timestamp with time zone, p_days integer) RETURNS timestamp with time zone
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    v_date DATE := (p_start AT TIME ZONE 'UTC')::date;
    v_left INT := COALESCE(p_days, 0);
    v_guard INT := 0;
BEGIN
    WHILE v_left > 0 LOOP
        v_date := v_date + 1;
        IF fn_sla_is_business_day(v_date) THEN
            v_left := v_left - 1;
        END IF;
        v_guard := v_guard + 1;
        IF v_guard > 20000 THEN
            RAISE EXCEPTION 'SLA due-date calculation did not converge (check the holiday calendar)';
        END IF;
    END LOOP;
    RETURN (v_date::timestamp + (p_start AT TIME ZONE 'UTC')::time) AT TIME ZONE 'UTC';
END;
$$;


--
-- Name: fn_sla_business_days_between(timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_sla_business_days_between(p_start timestamp with time zone, p_end timestamp with time zone) RETURNS integer
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    RETURN (
        SELECT COUNT(*)::INT
        FROM generate_series(
            ((p_start AT TIME ZONE 'UTC')::date + 1)::timestamp,
            (p_end AT TIME ZONE 'UTC')::date::timestamp,
            interval '1 day') AS g(d)
        WHERE fn_sla_is_business_day(g.d::date));
END;
$$;


--
-- Name: fn_sla_is_business_day(date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_sla_is_business_day(p_date date) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
    SELECT EXTRACT(ISODOW FROM p_date) < 6
       AND NOT EXISTS (SELECT 1 FROM sla_holiday h WHERE h.is_active AND h.holiday_date = p_date);
$$;


--
-- Name: fn_sla_open_status(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_sla_open_status() RETURNS TABLE(change_request_id uuid, stage text, entered_at timestamp with time zone, target_days integer, waiting_days integer, elapsed_days integer, due_at timestamp with time zone, stage_state text, e2e_target_days integer, e2e_elapsed_days integer, e2e_due_at timestamp with time zone, e2e_state text, overall_state text)
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    RETURN QUERY
    WITH base AS (
        SELECT cr.id AS b_cr, cr.submitted_at AS b_submitted, h.stage AS b_stage, h.entered_at AS b_entered,
               h.target_business_days AS b_target,
               COALESCE(cfg.pause_on_clarification, true) AS b_pause,
               COALESCE(cfg.at_risk_threshold_pct, 80) AS b_pct,
               e.target_business_days AS b_e2e_target
        FROM change_request cr
        JOIN change_request_stage_history h ON h.change_request_id = cr.id AND h.left_at IS NULL
        LEFT JOIN change_request_sla s ON s.change_request_id = cr.id
        LEFT JOIN sla_config cfg ON cfg.id = s.sla_config_id
        LEFT JOIN sla_target e ON e.sla_config_id = cfg.id AND e.change_type = cr.change_type AND e.stage = 'EndToEnd'
        WHERE cr.status <> 'Decisioned'
    ), waited AS (
        SELECT b.*,
               CASE WHEN b.b_pause THEN fn_sla_waiting_days(b.b_cr, b.b_entered, now()) ELSE 0 END AS w_stage,
               CASE WHEN b.b_pause THEN fn_sla_waiting_days(b.b_cr, b.b_submitted, now()) ELSE 0 END AS w_e2e
        FROM base b
    ), measured AS (
        SELECT w.*,
               GREATEST(fn_sla_business_days_between(w.b_entered, now()) - w.w_stage, 0) AS m_el_stage,
               GREATEST(fn_sla_business_days_between(w.b_submitted, now()) - w.w_e2e, 0) AS m_el_e2e,
               CASE WHEN w.b_target IS NULL THEN NULL ELSE fn_sla_add_business_days(w.b_entered, w.b_target + w.w_stage) END AS m_due_stage,
               CASE WHEN w.b_e2e_target IS NULL THEN NULL ELSE fn_sla_add_business_days(w.b_submitted, w.b_e2e_target + w.w_e2e) END AS m_due_e2e
        FROM waited w
    ), judged AS (
        SELECT m.*,
               fn_sla_state(now(), m.m_due_stage, m.m_el_stage, m.b_target, m.b_pct) AS j_stage_state,
               fn_sla_state(now(), m.m_due_e2e, m.m_el_e2e, m.b_e2e_target, m.b_pct) AS j_e2e_state
        FROM measured m
    )
    SELECT j.b_cr, j.b_stage, j.b_entered, j.b_target, j.w_stage, j.m_el_stage, j.m_due_stage, j.j_stage_state,
           j.b_e2e_target, j.m_el_e2e, j.m_due_e2e, j.j_e2e_state,
           CASE WHEN 'Breached' IN (j.j_stage_state, j.j_e2e_state) THEN 'Breached'
                WHEN 'AtRisk' IN (j.j_stage_state, j.j_e2e_state) THEN 'AtRisk'
                WHEN j.j_stage_state IS NULL AND j.j_e2e_state IS NULL THEN NULL
                ELSE 'OnTrack' END
    FROM judged j;
END;
$$;


--
-- Name: fn_sla_record_transition(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_sla_record_transition(p_change_request_id uuid, p_old_status text, p_new_status text) RETURNS void
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: fn_sla_state(timestamp with time zone, timestamp with time zone, integer, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_sla_state(p_now timestamp with time zone, p_due timestamp with time zone, p_elapsed integer, p_target integer, p_threshold_pct integer) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT CASE
        WHEN p_target IS NULL OR p_due IS NULL THEN NULL
        WHEN p_now > p_due THEN 'Breached'
        WHEN p_elapsed * 100 >= p_target * p_threshold_pct THEN 'AtRisk'
        ELSE 'OnTrack'
    END;
$$;


--
-- Name: fn_sla_waiting_days(uuid, timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_sla_waiting_days(p_change_request_id uuid, p_from timestamp with time zone, p_to timestamp with time zone) RETURNS integer
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    RETURN (
        SELECT COUNT(*)::INT
        FROM generate_series(
            ((p_from AT TIME ZONE 'UTC')::date + 1)::timestamp,
            (p_to AT TIME ZONE 'UTC')::date::timestamp,
            interval '1 day') AS g(d)
        WHERE fn_sla_is_business_day(g.d::date)
          AND EXISTS (
              SELECT 1 FROM change_request_clarification c
              WHERE c.change_request_id = p_change_request_id
                AND (c.created_at AT TIME ZONE 'UTC')::date < g.d::date
                AND g.d::date <= (COALESCE(c.answered_at, p_to) AT TIME ZONE 'UTC')::date));
END;
$$;


--
-- Name: fn_trg_sla_request_submitted(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_trg_sla_request_submitted() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM fn_sla_record_transition(NEW.id, NULL, NEW.status);
    RETURN NEW;
END;
$$;


--
-- Name: fn_trg_sla_status_changed(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_trg_sla_status_changed() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM fn_sla_record_transition(NEW.id, OLD.status, NEW.status);
    RETURN NEW;
END;
$$;


--
-- Name: func_addslaholiday(date, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_addslaholiday(p_holiday_date date, p_reason text, p_actor_user_id uuid) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id UUID := gen_random_uuid();
BEGIN
    IF p_holiday_date IS NULL THEN
        RAISE EXCEPTION 'A holiday date is required';
    END IF;
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'A reason is required to change the holiday calendar';
    END IF;
    IF EXISTS (SELECT 1 FROM sla_holiday WHERE is_active AND holiday_date = p_holiday_date) THEN
        RAISE EXCEPTION '% is already on the holiday calendar', to_char(p_holiday_date, 'YYYY-MM-DD');
    END IF;

    INSERT INTO sla_holiday (id, holiday_date, created_by_user_id, reason)
    VALUES (v_id, p_holiday_date, p_actor_user_id, p_reason);

    INSERT INTO audit_event (entity_type, entity_id, action, actor_user_id, actor_label, after_value, reason)
    VALUES ('SlaHoliday', v_id, 'ConfigChanged', p_actor_user_id, 'human',
            jsonb_build_object('holidayDate', to_char(p_holiday_date, 'YYYY-MM-DD'), 'change', 'Added'), p_reason);

    RETURN v_id;
END;
$$;


--
-- Name: func_appendauditevent(uuid, uuid, text, uuid, text, uuid, text, jsonb, jsonb, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_appendauditevent(p_change_request_id uuid, p_assessment_id uuid, p_entity_type text, p_entity_id uuid, p_action text, p_actor_user_id uuid, p_actor_label text, p_before_value jsonb, p_after_value jsonb, p_reason text) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id UUID := gen_random_uuid();
BEGIN
    INSERT INTO audit_event (id, change_request_id, assessment_id, entity_type, entity_id, action, actor_user_id, actor_label, before_value, after_value, reason)
    VALUES (v_id, p_change_request_id, p_assessment_id, p_entity_type, p_entity_id, p_action, p_actor_user_id, COALESCE(p_actor_label, 'system/AI'), p_before_value, p_after_value, p_reason);
    RETURN v_id;
END;
$$;


--
-- Name: func_attachdocument(uuid, text, text, text, text, uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_attachdocument(p_change_request_id uuid, p_file_name text, p_content_type text, p_storage_path text, p_extracted_text text, p_uploaded_by_user_id uuid, p_supersedes_attachment_id uuid DEFAULT NULL::uuid) RETURNS TABLE(id uuid, version_number integer)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id UUID := gen_random_uuid();
    v_version INT := 1;
BEGIN
    IF p_supersedes_attachment_id IS NOT NULL THEN
        SELECT a.version_number + 1 INTO v_version FROM change_request_attachment a WHERE a.id = p_supersedes_attachment_id;
    END IF;

    INSERT INTO change_request_attachment (id, change_request_id, file_name, content_type, storage_path, extracted_text, version_number, uploaded_by_user_id)
    VALUES (v_id, p_change_request_id, p_file_name, p_content_type, p_storage_path, p_extracted_text, v_version, p_uploaded_by_user_id);

    IF p_supersedes_attachment_id IS NOT NULL THEN
        -- DEF-008: "id" alone is ambiguous here - it matches both this function's "id" OUT
        -- parameter (from RETURNS TABLE) and the table's own id column, and PL/pgSQL raises
        -- "column reference is ambiguous" rather than picking one. Table-qualifying resolves it.
        UPDATE change_request_attachment SET superseded_by_attachment_id = v_id
            WHERE change_request_attachment.id = p_supersedes_attachment_id;
    END IF;

    INSERT INTO audit_event (change_request_id, entity_type, entity_id, action, actor_user_id, actor_label, after_value)
    VALUES (p_change_request_id, 'Attachment', v_id, 'Uploaded', p_uploaded_by_user_id, 'human',
            jsonb_build_object('fileName', p_file_name, 'version', v_version));

    RETURN QUERY SELECT v_id, v_version;
END;
$$;


--
-- Name: func_calculateandsaveriskscore(uuid, uuid, numeric, jsonb, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_calculateandsaveriskscore(p_assessment_id uuid, p_risk_category_id uuid, p_inherent_rating numeric, p_control_ids_credited jsonb, p_control_effectiveness numeric) RETURNS TABLE(id uuid, residual_rating numeric, mitigation_factor_applied numeric)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id UUID;
    v_mitigation_factor NUMERIC;
    v_residual NUMERIC;
BEGIN
    -- DEF-016: use the config that was active when THIS assessment started
    -- (assessment.created_at), not whatever is active right now - US-10.1 AC1: "takes effect only
    -- for assessments started after the change... existing in-flight assessments are unaffected."
    -- scoring_config is versioned per category (func_upsertScoringConfig never updates a row in
    -- place, only flips is_active and inserts a new one), so "the version in force at time T" is
    -- simply the most recent row created at or before T.
    SELECT sc.max_mitigation_factor INTO v_mitigation_factor
    FROM scoring_config sc
    JOIN assessment a ON a.id = p_assessment_id
    WHERE sc.risk_category_id = p_risk_category_id AND sc.created_at <= a.created_at
    ORDER BY sc.created_at DESC
    LIMIT 1;

    IF v_mitigation_factor IS NULL THEN
        RAISE EXCEPTION 'No scoring configuration was active for risk category % when this assessment started', p_risk_category_id;
    END IF;

    v_residual := p_inherent_rating - (p_control_effectiveness * v_mitigation_factor);

    INSERT INTO assessment_risk_score (
        id, assessment_id, risk_category_id, inherent_rating, control_ids_credited,
        control_effectiveness, mitigation_factor_applied, residual_rating, is_override, scored_by
    ) VALUES (
        gen_random_uuid(), p_assessment_id, p_risk_category_id, p_inherent_rating, COALESCE(p_control_ids_credited, '[]'::jsonb),
        p_control_effectiveness, v_mitigation_factor, v_residual, false, 'System'
    )
    ON CONFLICT (assessment_id, risk_category_id) DO UPDATE SET
        inherent_rating = EXCLUDED.inherent_rating, control_ids_credited = EXCLUDED.control_ids_credited,
        control_effectiveness = EXCLUDED.control_effectiveness, mitigation_factor_applied = EXCLUDED.mitigation_factor_applied,
        residual_rating = EXCLUDED.residual_rating, is_override = false, override_reason = NULL,
        scored_by = 'System', created_at = now()
    RETURNING assessment_risk_score.id INTO v_id;

    INSERT INTO audit_event (assessment_id, entity_type, entity_id, action, actor_label, after_value)
    VALUES (p_assessment_id, 'RiskScore', v_id, 'Calculated', 'system/AI',
            jsonb_build_object('riskCategoryId', p_risk_category_id, 'inherent', p_inherent_rating, 'residual', v_residual));

    RETURN QUERY SELECT v_id, v_residual, v_mitigation_factor;
END;
$$;


--
-- Name: func_castcommitteevote(uuid, uuid, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_castcommitteevote(p_assessment_id uuid, p_committee_member_user_id uuid, p_vote text, p_conditions_text text, p_rationale text) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id UUID;
    v_change_request_id UUID;
BEGIN
    SELECT change_request_id INTO v_change_request_id FROM assessment WHERE id = p_assessment_id;

    -- DEF-003: a second vote by the same member used to silently overwrite the first (ON CONFLICT
    -- DO UPDATE) - an accountable, individually-attributed vote (AC5) cannot be quietly replaced.
    -- ON CONFLICT DO NOTHING plus a null-id check rejects the re-vote instead.
    INSERT INTO committee_vote (assessment_id, committee_member_user_id, vote, conditions_text, rationale)
    VALUES (p_assessment_id, p_committee_member_user_id, p_vote, p_conditions_text, p_rationale)
    ON CONFLICT (assessment_id, committee_member_user_id) DO NOTHING
    RETURNING id INTO v_id;

    IF v_id IS NULL THEN
        RAISE EXCEPTION 'This committee member has already voted on this assessment; a cast vote cannot be changed.';
    END IF;

    INSERT INTO audit_event (change_request_id, assessment_id, entity_type, entity_id, action, actor_user_id, actor_label, after_value)
    VALUES (v_change_request_id, p_assessment_id, 'CommitteeVote', v_id, 'Voted', p_committee_member_user_id, 'human',
            jsonb_build_object('vote', p_vote, 'conditionsText', p_conditions_text, 'rationale', p_rationale));

    RETURN v_id;
END;
$$;


--
-- Name: func_correctextractedfield(uuid, text, text, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_correctextractedfield(p_change_request_id uuid, p_field_key text, p_new_value text, p_reason text, p_actor_user_id uuid) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id UUID;
    v_before JSONB;
BEGIN
    SELECT to_jsonb(f) INTO v_before FROM extracted_field f WHERE change_request_id = p_change_request_id AND field_key = p_field_key;

    UPDATE extracted_field
    SET field_value = p_new_value, source = 'AnalystCorrected', needs_review = false,
        confidence = NULL, updated_by_user_id = p_actor_user_id, updated_at = now()
    WHERE change_request_id = p_change_request_id AND field_key = p_field_key
    RETURNING id INTO v_id;

    INSERT INTO audit_event (change_request_id, entity_type, entity_id, action, actor_user_id, actor_label, before_value, after_value, reason)
    VALUES (p_change_request_id, 'ExtractedField', v_id, 'Corrected', p_actor_user_id, 'human',
            v_before, jsonb_build_object('fieldKey', p_field_key, 'value', p_new_value), p_reason);

    RETURN v_id;
END;
$$;


--
-- Name: func_createchangerequest(text, text, text, jsonb, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_createchangerequest(p_change_type text, p_title text, p_description text, p_type_specific_fields jsonb, p_submitted_by_user_id uuid) RETURNS TABLE(id uuid, request_number text, status text, submitted_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id UUID := gen_random_uuid();
    v_request_number TEXT := 'CR-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('change_request_number_seq')::text, 5, '0');
BEGIN
    INSERT INTO change_request (id, request_number, change_type, title, description, type_specific_fields, submitted_by_user_id)
    VALUES (v_id, v_request_number, p_change_type, p_title, p_description, COALESCE(p_type_specific_fields, '{}'::jsonb), p_submitted_by_user_id);

    INSERT INTO audit_event (change_request_id, entity_type, entity_id, action, actor_user_id, actor_label, after_value)
    VALUES (v_id, 'ChangeRequest', v_id, 'Created', p_submitted_by_user_id, 'human',
            jsonb_build_object('changeType', p_change_type, 'title', p_title, 'status', 'Submitted'));

    RETURN QUERY SELECT c.id, c.request_number, c.status, c.submitted_at FROM change_request c WHERE c.id = v_id;
END;
$$;


--
-- Name: func_createuser(text, text, text[], text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_createuser(p_email text, p_display_name text, p_roles text[], p_reason text, p_actor_user_id uuid) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id UUID := gen_random_uuid();
    v_role TEXT;
BEGIN
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'A reason is required to create a user';
    END IF;
    IF p_roles IS NULL OR array_length(p_roles, 1) IS NULL THEN
        RAISE EXCEPTION 'A user must be created with at least one role';
    END IF;

    INSERT INTO app_user (id, auth0_subject, email, display_name)
    VALUES (v_id, NULL, p_email, p_display_name);

    FOREACH v_role IN ARRAY p_roles LOOP
        INSERT INTO app_user_role (user_id, role, granted_by_user_id, reason)
        VALUES (v_id, v_role, p_actor_user_id, p_reason);
    END LOOP;

    INSERT INTO audit_event (entity_type, entity_id, action, actor_user_id, actor_label, after_value, reason)
    VALUES ('AppUser', v_id, 'Created', p_actor_user_id, 'human',
            jsonb_build_object('email', p_email, 'displayName', p_display_name, 'roles', p_roles), p_reason);

    RETURN v_id;
END;
$$;


--
-- Name: func_editnarrativesection(uuid, uuid, text, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_editnarrativesection(p_assessment_id uuid, p_risk_category_id uuid, p_new_text text, p_reason text, p_actor_user_id uuid) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id UUID;
    v_before JSONB;
BEGIN
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'A reason is required to edit an AI-drafted narrative section';
    END IF;

    SELECT to_jsonb(s) INTO v_before FROM assessment_narrative_section s
        WHERE assessment_id = p_assessment_id AND risk_category_id = p_risk_category_id;

    UPDATE assessment_narrative_section
    SET narrative_text = p_new_text, status = 'AnalystEdited', updated_by_user_id = p_actor_user_id, updated_at = now()
    WHERE assessment_id = p_assessment_id AND risk_category_id = p_risk_category_id
    RETURNING id INTO v_id;

    INSERT INTO audit_event (assessment_id, entity_type, entity_id, action, actor_user_id, actor_label, before_value, after_value, reason)
    VALUES (p_assessment_id, 'NarrativeSection', v_id, 'AnalystEdited', p_actor_user_id, 'human',
            v_before, jsonb_build_object('riskCategoryId', p_risk_category_id, 'text', p_new_text), p_reason);

    RETURN v_id;
END;
$$;


--
-- Name: func_finalizeassessment(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_finalizeassessment(p_assessment_id uuid, p_actor_user_id uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: func_getallactiveworkflowrules(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_getallactiveworkflowrules() RETURNS TABLE(id uuid, rule_key text, rule_value_json jsonb, is_active boolean, created_at timestamp with time zone)
    LANGUAGE sql STABLE
    AS $$
    SELECT id, rule_key, rule_value, is_active, created_at
    FROM workflow_rule WHERE is_active = true
    ORDER BY rule_key;
$$;


--
-- Name: func_getallchangerequests(text, text, text, text, text, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_getallchangerequests(p_status text DEFAULT NULL::text, p_change_type text DEFAULT NULL::text, p_search text DEFAULT NULL::text, p_sort_by text DEFAULT NULL::text, p_sort_dir text DEFAULT NULL::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 10) RETURNS TABLE(id uuid, request_number text, change_type text, title text, status text, submitted_at timestamp with time zone, days_elapsed integer, due_at timestamp with time zone, sla_state text, total_count bigint)
    LANGUAGE plpgsql STABLE
    AS $_$
DECLARE
    v_column TEXT := CASE p_sort_by
        WHEN 'requestNumber' THEN 'c.request_number'
        WHEN 'changeType' THEN 'c.change_type'
        WHEN 'title' THEN 'c.title'
        WHEN 'status' THEN 'c.status'
        WHEN 'daysElapsed' THEN 'c.submitted_at'
        ELSE 'c.submitted_at'
    END;
    -- days_elapsed counts down as submitted_at counts up, so "largest days elapsed first" is
    -- submitted_at ASC, not DESC - flip the direction for that one column only.
    v_direction TEXT := CASE
        WHEN p_sort_by = 'daysElapsed' THEN (CASE WHEN lower(p_sort_dir) = 'asc' THEN 'DESC' ELSE 'ASC' END)
        ELSE (CASE WHEN lower(p_sort_dir) = 'desc' THEN 'DESC' ELSE 'ASC' END)
    END;
    v_page INT := GREATEST(COALESCE(p_page, 1), 1);
    v_page_size INT := LEAST(GREATEST(COALESCE(p_page_size, 10), 1), 200);
BEGIN
    -- No sort picked yet (first load) - keep this function's original default: newest first.
    IF p_sort_by IS NULL THEN
        v_column := 'c.submitted_at';
        v_direction := 'DESC';
    END IF;

    -- Epic 19: due_at is when the DECISION is due (the overall target) - what a requester or analyst wants to
    -- know; the current stage's own due date is only used when no overall target is set.
    RETURN QUERY EXECUTE format(
        'SELECT c.id, c.request_number, c.change_type, c.title, c.status, c.submitted_at,
                EXTRACT(DAY FROM now() - c.submitted_at)::INT AS days_elapsed,
                CASE WHEN c.status = ''Decisioned'' THEN NULL ELSE COALESCE(o.e2e_due_at, o.due_at) END AS due_at,
                CASE WHEN c.status = ''Decisioned'' THEN (CASE WHEN ms.e2e_met THEN ''Met'' WHEN ms.e2e_met = false THEN ''Missed'' END)
                     ELSE o.overall_state END AS sla_state,
                COUNT(*) OVER()::BIGINT AS total_count
         FROM change_request c
         LEFT JOIN fn_sla_open_status() o ON o.change_request_id = c.id
         LEFT JOIN change_request_sla ms ON ms.change_request_id = c.id
         WHERE ($1::TEXT IS NULL OR c.status = $1)
           AND ($2::TEXT IS NULL OR c.change_type = $2)
           AND ($3::TEXT IS NULL OR c.title ILIKE ''%%'' || $3 || ''%%'' OR c.request_number ILIKE ''%%'' || $3 || ''%%'')
         ORDER BY %s %s NULLS LAST, c.id
         LIMIT $4 OFFSET $5',
        v_column, v_direction
    ) USING p_status, p_change_type, p_search, v_page_size, (v_page - 1) * v_page_size;
END;
$_$;


--
-- Name: func_getallriskcategories(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_getallriskcategories() RETURNS TABLE(id uuid, code text, name text, citation_section text)
    LANGUAGE sql STABLE
    AS $$
    SELECT id, code, name, citation_section FROM risk_category ORDER BY name;
$$;


--
-- Name: func_getallusers(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_getallusers() RETURNS TABLE(id uuid, display_name text, email text, roles text[])
    LANGUAGE sql STABLE
    AS $$
    SELECT u.id, u.display_name, u.email, array_agg(ur.role ORDER BY ur.role)
    FROM app_user u
    JOIN app_user_role ur ON ur.user_id = u.id
    WHERE u.is_active = true
    GROUP BY u.id, u.display_name, u.email
    ORDER BY u.display_name;
$$;


--
-- Name: func_getallusersforadmin(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_getallusersforadmin() RETURNS TABLE(id uuid, auth0_subject text, email text, display_name text, roles text[], is_active boolean, created_at timestamp with time zone)
    LANGUAGE sql STABLE
    AS $$
    SELECT
        u.id, u.auth0_subject, u.email, u.display_name,
        coalesce(array_agg(ur.role ORDER BY ur.role) FILTER (WHERE ur.role IS NOT NULL), '{}'),
        u.is_active, u.created_at
    FROM app_user u
    LEFT JOIN app_user_role ur ON ur.user_id = u.id
    GROUP BY u.id, u.auth0_subject, u.email, u.display_name, u.is_active, u.created_at
    ORDER BY u.display_name;
$$;


--
-- Name: func_getassessmentbychangerequest(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_getassessmentbychangerequest(p_change_request_id uuid) RETURNS TABLE(id uuid, change_request_id uuid, status text, finalized_by_user_id uuid, finalized_at timestamp with time zone, created_at timestamp with time zone)
    LANGUAGE sql STABLE
    AS $$
    SELECT a.id, a.change_request_id, a.status, a.finalized_by_user_id, a.finalized_at, a.created_at
    FROM assessment a WHERE a.change_request_id = p_change_request_id;
$$;


--
-- Name: func_getassessmentbyid(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_getassessmentbyid(p_assessment_id uuid) RETURNS TABLE(id uuid, change_request_id uuid, status text, finalized_by_user_id uuid, finalized_at timestamp with time zone, created_at timestamp with time zone)
    LANGUAGE sql STABLE
    AS $$
    SELECT a.id, a.change_request_id, a.status, a.finalized_by_user_id, a.finalized_at, a.created_at
    FROM assessment a WHERE a.id = p_assessment_id;
$$;


--
-- Name: func_getattachments(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_getattachments(p_change_request_id uuid) RETURNS TABLE(id uuid, file_name text, content_type text, storage_path text, version_number integer, uploaded_at timestamp with time zone)
    LANGUAGE sql STABLE
    AS $$
    SELECT a.id, a.file_name, a.content_type, a.storage_path, a.version_number, a.uploaded_at
    FROM change_request_attachment a
    WHERE a.change_request_id = p_change_request_id AND a.superseded_by_attachment_id IS NULL
    ORDER BY a.uploaded_at;
$$;


--
-- Name: func_getattachmenttext(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_getattachmenttext(p_change_request_id uuid, p_attachment_id uuid) RETURNS text
    LANGUAGE sql STABLE
    AS $$
    SELECT extracted_text FROM change_request_attachment
    WHERE id = p_attachment_id AND change_request_id = p_change_request_id;
$$;


--
-- Name: func_getaudittrailforrequest(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_getaudittrailforrequest(p_change_request_id uuid) RETURNS TABLE(id uuid, entity_type text, entity_id uuid, action text, actor_user_id uuid, actor_name text, actor_label text, before_value_json jsonb, after_value_json jsonb, reason text, created_at timestamp with time zone)
    LANGUAGE sql STABLE
    AS $$
    SELECT e.id, e.entity_type, e.entity_id, e.action, e.actor_user_id,
           u.display_name, e.actor_label, e.before_value, e.after_value, e.reason, e.created_at
    FROM audit_event e
    LEFT JOIN app_user u ON u.id = e.actor_user_id
    LEFT JOIN assessment a ON a.change_request_id = p_change_request_id
    WHERE e.change_request_id = p_change_request_id OR e.assessment_id = a.id
    ORDER BY e.created_at ASC;
$$;


--
-- Name: func_getcategorymapping(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_getcategorymapping(p_assessment_id uuid) RETURNS TABLE(id uuid, risk_category_id uuid, category_code text, category_name text, citation_section text, source text, ai_citation text, is_active boolean, created_at timestamp with time zone, analyst_reason text)
    LANGUAGE sql STABLE
    AS $$
    SELECT m.id, m.risk_category_id, rc.code, rc.name, rc.citation_section, m.source, m.ai_citation, m.is_active, m.created_at,
           latest_reason.reason
    FROM assessment_category_mapping m
    JOIN risk_category rc ON rc.id = m.risk_category_id
    LEFT JOIN LATERAL (
        SELECT ae.reason
        FROM audit_event ae
        WHERE ae.entity_type = 'CategoryMapping' AND ae.entity_id = m.id AND ae.action = 'Overridden'
        ORDER BY ae.created_at DESC
        LIMIT 1
    ) latest_reason ON true
    WHERE m.assessment_id = p_assessment_id
    ORDER BY m.created_at;
$$;


--
-- Name: func_getchangerequestbyid(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_getchangerequestbyid(p_change_request_id uuid) RETURNS TABLE(id uuid, request_number text, change_type text, title text, description text, type_specific_fields_json jsonb, status text, submitted_by_user_id uuid, submitted_at timestamp with time zone)
    LANGUAGE sql STABLE
    AS $$
    SELECT c.id, c.request_number, c.change_type, c.title, c.description, c.type_specific_fields,
           c.status, c.submitted_by_user_id, c.submitted_at
    FROM change_request c WHERE c.id = p_change_request_id;
$$;


--
-- Name: func_getchangerequestsforuser(uuid, text, text, text, text, text, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_getchangerequestsforuser(p_user_id uuid, p_status text DEFAULT NULL::text, p_change_type text DEFAULT NULL::text, p_search text DEFAULT NULL::text, p_sort_by text DEFAULT NULL::text, p_sort_dir text DEFAULT NULL::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 10) RETURNS TABLE(id uuid, request_number text, change_type text, title text, status text, submitted_at timestamp with time zone, days_elapsed integer, decision_resolution text, decision_conditions_text text, due_at timestamp with time zone, sla_state text, total_count bigint)
    LANGUAGE plpgsql STABLE
    AS $_$
DECLARE
    v_column TEXT := CASE p_sort_by
        WHEN 'requestNumber' THEN 'c.request_number'
        WHEN 'changeType' THEN 'c.change_type'
        WHEN 'title' THEN 'c.title'
        WHEN 'status' THEN 'c.status'
        WHEN 'daysElapsed' THEN 'c.submitted_at'
        ELSE 'c.submitted_at'
    END;
    -- days_elapsed counts down as submitted_at counts up, so "largest days elapsed first" is
    -- submitted_at ASC, not DESC - flip the direction for that one column only.
    v_direction TEXT := CASE
        WHEN p_sort_by = 'daysElapsed' THEN (CASE WHEN lower(p_sort_dir) = 'asc' THEN 'DESC' ELSE 'ASC' END)
        ELSE (CASE WHEN lower(p_sort_dir) = 'desc' THEN 'DESC' ELSE 'ASC' END)
    END;
    v_page INT := GREATEST(COALESCE(p_page, 1), 1);
    v_page_size INT := LEAST(GREATEST(COALESCE(p_page_size, 10), 1), 200);
BEGIN
    -- No sort picked yet (first load) - keep this function's original default: newest first.
    IF p_sort_by IS NULL THEN
        v_column := 'c.submitted_at';
        v_direction := 'DESC';
    END IF;

    -- Epic 19: due_at is when the DECISION is due (the overall target) - what a requester or analyst wants to
    -- know; the current stage's own due date is only used when no overall target is set.
    RETURN QUERY EXECUTE format(
        'SELECT c.id, c.request_number, c.change_type, c.title, c.status, c.submitted_at,
                EXTRACT(DAY FROM now() - c.submitted_at)::INT AS days_elapsed,
                d.resolution, d.conditions_text,
                CASE WHEN c.status = ''Decisioned'' THEN NULL ELSE COALESCE(o.e2e_due_at, o.due_at) END AS due_at,
                CASE WHEN c.status = ''Decisioned'' THEN (CASE WHEN ms.e2e_met THEN ''Met'' WHEN ms.e2e_met = false THEN ''Missed'' END)
                     ELSE o.overall_state END AS sla_state,
                COUNT(*) OVER()::BIGINT AS total_count
         FROM change_request c
         LEFT JOIN assessment a ON a.change_request_id = c.id
         LEFT JOIN committee_decision d ON d.assessment_id = a.id
         LEFT JOIN fn_sla_open_status() o ON o.change_request_id = c.id
         LEFT JOIN change_request_sla ms ON ms.change_request_id = c.id
         WHERE c.submitted_by_user_id = $1
           AND ($2::TEXT IS NULL OR c.status = $2)
           AND ($3::TEXT IS NULL OR c.change_type = $3)
           AND ($4::TEXT IS NULL OR c.title ILIKE ''%%'' || $4 || ''%%'' OR c.request_number ILIKE ''%%'' || $4 || ''%%'')
         ORDER BY %s %s NULLS LAST, c.id
         LIMIT $5 OFFSET $6',
        v_column, v_direction
    ) USING p_user_id, p_status, p_change_type, p_search, v_page_size, (v_page - 1) * v_page_size;
END;
$_$;


--
-- Name: func_getchangetypecategorydefaults(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_getchangetypecategorydefaults(p_change_type text) RETURNS TABLE(risk_category_id uuid, code text, name text, citation_section text, weight text)
    LANGUAGE sql STABLE
    AS $$
    SELECT rc.id, rc.code, rc.name, rc.citation_section, m.weight
    FROM change_request_type_category_map m
    JOIN risk_category rc ON rc.id = m.risk_category_id
    WHERE m.change_type = p_change_type
    ORDER BY m.weight; -- 'Primary' sorts before 'Secondary'
$$;


--
-- Name: func_getcommitteedecision(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_getcommitteedecision(p_assessment_id uuid) RETURNS TABLE(id uuid, resolution text, conditions_text text, decided_at timestamp with time zone)
    LANGUAGE sql STABLE
    AS $$
    SELECT d.id, d.resolution, d.conditions_text, d.decided_at
    FROM committee_decision d WHERE d.assessment_id = p_assessment_id;
$$;


--
-- Name: func_getcommitteequeue(text, text, text, text, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_getcommitteequeue(p_change_type text DEFAULT NULL::text, p_search text DEFAULT NULL::text, p_sort_by text DEFAULT NULL::text, p_sort_dir text DEFAULT NULL::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 10) RETURNS TABLE(assessment_id uuid, change_request_id uuid, request_number text, change_type text, title text, routed_at timestamp with time zone, due_at timestamp with time zone, sla_state text, total_count bigint)
    LANGUAGE plpgsql STABLE
    AS $_$
DECLARE
    v_column TEXT := CASE p_sort_by
        WHEN 'requestNumber' THEN 'c.request_number'
        WHEN 'changeType' THEN 'c.change_type'
        WHEN 'title' THEN 'c.title'
        WHEN 'routedAt' THEN 'a.finalized_at'
        ELSE 'a.finalized_at'
    END;
    v_direction TEXT := CASE WHEN lower(p_sort_dir) = 'desc' THEN 'DESC' ELSE 'ASC' END;
    v_page INT := GREATEST(COALESCE(p_page, 1), 1);
    v_page_size INT := LEAST(GREATEST(COALESCE(p_page_size, 10), 1), 200);
BEGIN
    -- No sort picked yet (first load) - keep this function's original default: oldest-routed first.
    IF p_sort_by IS NULL THEN
        v_column := 'a.finalized_at';
        v_direction := 'ASC';
    END IF;

    RETURN QUERY EXECUTE format(
        'SELECT a.id, c.id, c.request_number, c.change_type, c.title, a.finalized_at,
                COALESCE(o.e2e_due_at, o.due_at) AS due_at, o.overall_state AS sla_state,
                COUNT(*) OVER()::BIGINT AS total_count
         FROM change_request c
         JOIN assessment a ON a.change_request_id = c.id
         LEFT JOIN fn_sla_open_status() o ON o.change_request_id = c.id
         WHERE c.status = ''PendingCommittee''
           AND ($1::TEXT IS NULL OR c.change_type = $1)
           AND ($2::TEXT IS NULL OR c.title ILIKE ''%%'' || $2 || ''%%'' OR c.request_number ILIKE ''%%'' || $2 || ''%%'')
         ORDER BY %s %s NULLS LAST, c.id
         LIMIT $3 OFFSET $4',
        v_column, v_direction
    ) USING p_change_type, p_search, v_page_size, (v_page - 1) * v_page_size;
END;
$_$;


--
-- Name: func_getcommitteevotes(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_getcommitteevotes(p_assessment_id uuid) RETURNS TABLE(id uuid, committee_member_user_id uuid, committee_member_name text, vote text, conditions_text text, rationale text, voted_at timestamp with time zone)
    LANGUAGE sql STABLE
    AS $$
    SELECT v.id, v.committee_member_user_id, u.display_name, v.vote, v.conditions_text, v.rationale, v.voted_at
    FROM committee_vote v
    JOIN app_user u ON u.id = v.committee_member_user_id
    WHERE v.assessment_id = p_assessment_id
    ORDER BY v.voted_at;
$$;


--
-- Name: func_getcontrols(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_getcontrols(p_risk_category_id uuid) RETURNS TABLE(id uuid, name text, description text)
    LANGUAGE sql STABLE
    AS $$
    SELECT c.id, c.name, c.description FROM control c WHERE c.risk_category_id = p_risk_category_id;
$$;


--
-- Name: func_getcustomerbyid(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_getcustomerbyid(p_id uuid) RETURNS TABLE(id uuid, customer_name text, customer_type text, customer_geography text, segment_classification text, kyc_status text, risk_flag text)
    LANGUAGE sql
    AS $$
    SELECT id, customer_name, customer_type, customer_geography, segment_classification, kyc_status, risk_flag
    FROM mock_systems.crm_customer
    WHERE id = p_id;
$$;


--
-- Name: func_getexternalsnapshot(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_getexternalsnapshot(p_change_request_id uuid) RETURNS TABLE(id uuid, change_request_id uuid, mock_customer_id uuid, customer_risk_context_json jsonb, mock_product_id uuid, product_risk_context_json jsonb, mock_vendor_id uuid, vendor_risk_context_json jsonb, ingested_at timestamp with time zone)
    LANGUAGE sql
    AS $$
    SELECT
        s.id, s.change_request_id,
        s.mock_customer_id, s.customer_risk_context,
        s.mock_product_id, s.product_risk_context,
        s.mock_vendor_id, s.vendor_risk_context,
        s.ingested_at
    FROM change_request_external_snapshot s
    WHERE s.change_request_id = p_change_request_id;
$$;


--
-- Name: func_getextractedfields(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_getextractedfields(p_change_request_id uuid) RETURNS TABLE(id uuid, field_key text, field_value text, confidence numeric, needs_review boolean, source_excerpt text, source text, updated_at timestamp with time zone)
    LANGUAGE sql STABLE
    AS $$
    SELECT f.id, f.field_key, f.field_value, f.confidence, f.needs_review, f.source_excerpt, f.source, f.updated_at
    FROM extracted_field f WHERE f.change_request_id = p_change_request_id;
$$;


--
-- Name: func_getnarrativesections(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_getnarrativesections(p_assessment_id uuid) RETURNS TABLE(id uuid, risk_category_id uuid, category_name text, narrative_text text, status text, unsupported_claim_flags_json jsonb, updated_at timestamp with time zone)
    LANGUAGE sql STABLE
    AS $$
    SELECT s.id, s.risk_category_id, rc.name, s.narrative_text, s.status, s.unsupported_claim_flags, s.updated_at
    FROM assessment_narrative_section s
    JOIN risk_category rc ON rc.id = s.risk_category_id
    WHERE s.assessment_id = p_assessment_id;
$$;


--
-- Name: func_getorcreateassessment(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_getorcreateassessment(p_change_request_id uuid) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id UUID;
BEGIN
    SELECT id INTO v_id FROM assessment WHERE change_request_id = p_change_request_id;
    IF v_id IS NULL THEN
        v_id := gen_random_uuid();
        INSERT INTO assessment (id, change_request_id) VALUES (v_id, p_change_request_id);
        UPDATE change_request SET status = 'InAssessment' WHERE id = p_change_request_id AND status = 'Submitted';
    END IF;
    RETURN v_id;
END;
$$;


--
-- Name: func_getpolicyreliance(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_getpolicyreliance(p_assessment_id uuid) RETURNS TABLE(id uuid, risk_category_id uuid, policy_chunk_id uuid, decision text, decided_at timestamp with time zone, section_ref text, chunk_text text)
    LANGUAGE sql STABLE
    AS $$
    SELECT r.id, r.risk_category_id, r.policy_chunk_id, r.decision, r.decided_at, pc.section_ref, pc.chunk_text
    FROM assessment_policy_reliance r
    JOIN policy_chunk pc ON pc.id = r.policy_chunk_id
    WHERE r.assessment_id = p_assessment_id;
$$;


--
-- Name: func_getproductbyid(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_getproductbyid(p_id uuid) RETURNS TABLE(id uuid, product_name text, product_type text, features_json jsonb, product_geography text, launch_change_type text, go_live_flag boolean, risk_rating text)
    LANGUAGE sql
    AS $$
    SELECT id, product_name, product_type, features_json, product_geography, launch_change_type, go_live_flag, risk_rating
    FROM mock_systems.core_banking_product
    WHERE id = p_id;
$$;


--
-- Name: func_getrequestsla(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_getrequestsla(p_change_request_id uuid) RETURNS TABLE(scope text, stage text, entered_at timestamp with time zone, left_at timestamp with time zone, target_days integer, elapsed_days integer, waiting_days integer, due_at timestamp with time zone, state text)
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    RETURN QUERY
    SELECT 'Stage'::TEXT, o.stage, o.entered_at, NULL::TIMESTAMPTZ, o.target_days,
           o.elapsed_days, o.waiting_days, o.due_at, o.stage_state
    FROM fn_sla_open_status() o WHERE o.change_request_id = p_change_request_id
    UNION ALL
    SELECT 'EndToEnd'::TEXT, NULL::TEXT, cr.submitted_at, NULL::TIMESTAMPTZ, o.e2e_target_days,
           o.e2e_elapsed_days, NULL::INT, o.e2e_due_at, o.e2e_state
    FROM fn_sla_open_status() o JOIN change_request cr ON cr.id = o.change_request_id
    WHERE o.change_request_id = p_change_request_id
    UNION ALL
    SELECT 'EndToEnd'::TEXT, NULL::TEXT, cr.submitted_at, s.decided_at, t.target_business_days,
           s.e2e_actual_business_days, NULL::INT, NULL::TIMESTAMPTZ,
           CASE WHEN s.e2e_met THEN 'Met' WHEN s.e2e_met = false THEN 'Missed' END
    FROM change_request_sla s
    JOIN change_request cr ON cr.id = s.change_request_id
    LEFT JOIN sla_target t ON t.sla_config_id = s.sla_config_id AND t.change_type = cr.change_type AND t.stage = 'EndToEnd'
    WHERE s.change_request_id = p_change_request_id AND s.decided_at IS NOT NULL
    UNION ALL
    SELECT 'Completed'::TEXT, h.stage, h.entered_at, h.left_at, h.target_business_days,
           h.actual_business_days, NULL::INT, NULL::TIMESTAMPTZ,
           CASE WHEN h.met_sla THEN 'Met' WHEN h.met_sla = false THEN 'Missed' END
    FROM change_request_stage_history h
    WHERE h.change_request_id = p_change_request_id AND h.left_at IS NOT NULL;
END;
$$;


--
-- Name: func_getriskscores(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_getriskscores(p_assessment_id uuid) RETURNS TABLE(id uuid, risk_category_id uuid, category_name text, inherent_rating numeric, control_effectiveness numeric, mitigation_factor_applied numeric, residual_rating numeric, is_override boolean, override_reason text, scored_by text, created_at timestamp with time zone)
    LANGUAGE sql STABLE
    AS $$
    SELECT s.id, s.risk_category_id, rc.name, s.inherent_rating, s.control_effectiveness,
           s.mitigation_factor_applied, s.residual_rating, s.is_override, s.override_reason, s.scored_by, s.created_at
    FROM assessment_risk_score s
    JOIN risk_category rc ON rc.id = s.risk_category_id
    WHERE s.assessment_id = p_assessment_id;
$$;


--
-- Name: func_getslaconfig(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_getslaconfig() RETURNS TABLE(id uuid, version_number integer, at_risk_threshold_pct integer, pause_on_clarification boolean, reason text, created_at timestamp with time zone)
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    RETURN QUERY
    SELECT c.id, c.version_number, c.at_risk_threshold_pct, c.pause_on_clarification, c.reason, c.created_at
    FROM sla_config c
    WHERE c.is_active;
END;
$$;


--
-- Name: func_getslaholidays(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_getslaholidays() RETURNS TABLE(id uuid, holiday_date date, reason text, created_at timestamp with time zone)
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    RETURN QUERY
    SELECT h.id, h.holiday_date, h.reason, h.created_at
    FROM sla_holiday h
    WHERE h.is_active
    ORDER BY h.holiday_date;
END;
$$;


--
-- Name: func_getslaperformance(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_getslaperformance(p_change_type text DEFAULT NULL::text) RETURNS TABLE(change_type text, stage text, sample_count integer, target_days integer, median_days numeric, p90_days numeric, met_percent numeric)
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    RETURN QUERY
    WITH finished AS (
        SELECT cr.change_type AS f_type, h.stage AS f_stage, h.actual_business_days AS f_days, h.met_sla AS f_met
        FROM change_request_stage_history h
        JOIN change_request cr ON cr.id = h.change_request_id
        WHERE h.left_at IS NOT NULL AND h.actual_business_days IS NOT NULL
        UNION ALL
        SELECT cr.change_type, 'EndToEnd', s.e2e_actual_business_days, s.e2e_met
        FROM change_request_sla s
        JOIN change_request cr ON cr.id = s.change_request_id
        WHERE s.decided_at IS NOT NULL AND s.e2e_actual_business_days IS NOT NULL
    ), per_type AS (
        SELECT f.f_type AS p_type, f.f_stage AS p_stage, COUNT(*)::INT AS p_count,
               (percentile_cont(0.5) WITHIN GROUP (ORDER BY f.f_days))::NUMERIC(6,1) AS p_median,
               (percentile_cont(0.9) WITHIN GROUP (ORDER BY f.f_days))::NUMERIC(6,1) AS p_p90,
               ROUND(100.0 * COUNT(*) FILTER (WHERE f.f_met) / NULLIF(COUNT(*) FILTER (WHERE f.f_met IS NOT NULL), 0), 1) AS p_met
        FROM finished f
        WHERE p_change_type IS NULL OR f.f_type = p_change_type
        GROUP BY f.f_type, f.f_stage
    ), overall AS (
        SELECT 'All'::TEXT AS o_type, 'EndToEnd'::TEXT AS o_stage, COUNT(*)::INT AS o_count,
               (percentile_cont(0.5) WITHIN GROUP (ORDER BY f.f_days))::NUMERIC(6,1) AS o_median,
               (percentile_cont(0.9) WITHIN GROUP (ORDER BY f.f_days))::NUMERIC(6,1) AS o_p90,
               ROUND(100.0 * COUNT(*) FILTER (WHERE f.f_met) / NULLIF(COUNT(*) FILTER (WHERE f.f_met IS NOT NULL), 0), 1) AS o_met
        FROM finished f
        WHERE f.f_stage = 'EndToEnd' AND (p_change_type IS NULL OR f.f_type = p_change_type)
        HAVING COUNT(*) > 0
    )
    SELECT r.r_type, r.r_stage, r.r_count, r.r_target, r.r_median, r.r_p90, r.r_met
    FROM (
        SELECT p.p_type AS r_type, p.p_stage AS r_stage, p.p_count AS r_count, t.target_business_days AS r_target,
               p.p_median AS r_median, p.p_p90 AS r_p90, p.p_met AS r_met
        FROM per_type p
        LEFT JOIN sla_config c ON c.is_active
        LEFT JOIN sla_target t ON t.sla_config_id = c.id AND t.change_type = p.p_type AND t.stage = p.p_stage
        UNION ALL
        SELECT ov.o_type, ov.o_stage, ov.o_count, NULL::INT, ov.o_median, ov.o_p90, ov.o_met FROM overall ov
    ) r
    ORDER BY CASE r.r_type WHEN 'All' THEN 1 ELSE 0 END, r.r_type,
             CASE r.r_stage WHEN 'Submitted' THEN 0 WHEN 'InAssessment' THEN 1 WHEN 'PendingCommittee' THEN 2 ELSE 3 END;
END;
$$;


--
-- Name: func_getslasummary(text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_getslasummary(p_stage text DEFAULT NULL::text, p_change_type text DEFAULT NULL::text, p_search text DEFAULT NULL::text) RETURNS TABLE(overall_state text, request_count integer)
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    v_search TEXT := lower(NULLIF(btrim(COALESCE(p_search, '')), ''));
BEGIN
    RETURN QUERY
    SELECT o.overall_state, COUNT(*)::INT
    FROM fn_sla_open_status() o
    JOIN change_request cr ON cr.id = o.change_request_id
    WHERE (p_stage IS NULL OR o.stage = p_stage)
      AND (p_change_type IS NULL OR cr.change_type = p_change_type)
      AND (v_search IS NULL
           OR position(v_search IN lower(cr.title)) > 0
           OR position(v_search IN lower(cr.request_number)) > 0)
    GROUP BY o.overall_state;
END;
$$;


--
-- Name: func_getslatargets(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_getslatargets() RETURNS TABLE(change_type text, stage text, target_business_days integer)
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    RETURN QUERY
    SELECT t.change_type, t.stage, t.target_business_days
    FROM sla_target t
    JOIN sla_config c ON c.id = t.sla_config_id AND c.is_active
    ORDER BY t.change_type,
             CASE t.stage WHEN 'Submitted' THEN 0 WHEN 'InAssessment' THEN 1 WHEN 'PendingCommittee' THEN 2 ELSE 3 END;
END;
$$;


--
-- Name: func_getslaview(text, text, text, text, text, text, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_getslaview(p_stage text DEFAULT NULL::text, p_change_type text DEFAULT NULL::text, p_state text DEFAULT NULL::text, p_search text DEFAULT NULL::text, p_sort_by text DEFAULT NULL::text, p_sort_dir text DEFAULT NULL::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 10) RETURNS TABLE(change_request_id uuid, request_number text, title text, change_type text, stage text, entered_at timestamp with time zone, target_days integer, elapsed_days integer, waiting_days integer, due_at timestamp with time zone, stage_state text, e2e_due_at timestamp with time zone, e2e_state text, overall_state text, days_overdue integer, e2e_target_days integer, e2e_elapsed_days integer, total_count bigint)
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    v_key TEXT := COALESCE(NULLIF(p_sort_by, ''), 'urgency');
    v_asc BOOLEAN := lower(COALESCE(p_sort_dir, 'asc')) <> 'desc';
    v_page INT := GREATEST(COALESCE(p_page, 1), 1);
    v_size INT := LEAST(GREATEST(COALESCE(p_page_size, 10), 1), 200);
    v_search TEXT := lower(NULLIF(btrim(COALESCE(p_search, '')), ''));
BEGIN
    RETURN QUERY
    SELECT v.v_cr, v.v_number, v.v_title, v.v_type, v.v_stage,
           v.v_entered, v.v_target, v.v_elapsed, v.v_waiting, v.v_due,
           v.v_stage_state, v.v_e2e_due, v.v_e2e_state, v.v_overall, v.v_overdue,
           v.v_e2e_target, v.v_e2e_elapsed, v.v_total
    FROM (
        SELECT o.change_request_id AS v_cr, cr.request_number AS v_number, cr.title AS v_title,
               cr.change_type AS v_type, o.stage AS v_stage, o.entered_at AS v_entered,
               o.target_days AS v_target, o.elapsed_days AS v_elapsed, o.waiting_days AS v_waiting,
               o.due_at AS v_due, o.stage_state AS v_stage_state, o.e2e_due_at AS v_e2e_due,
               o.e2e_state AS v_e2e_state, o.overall_state AS v_overall,
               GREATEST(
                   CASE WHEN o.stage_state = 'Breached' THEN fn_sla_business_days_between(o.due_at, now()) ELSE 0 END,
                   CASE WHEN o.e2e_state = 'Breached' THEN fn_sla_business_days_between(o.e2e_due_at, now()) ELSE 0 END
               ) AS v_overdue,
               o.e2e_target_days AS v_e2e_target, o.e2e_elapsed_days AS v_e2e_elapsed,
               -- How far through its target a request is: the further of its stage and overall position
               -- (GREATEST ignores a null, so a stage with no target of its own just uses the overall one).
               GREATEST(o.elapsed_days::NUMERIC / NULLIF(o.target_days, 0),
                        o.e2e_elapsed_days::NUMERIC / NULLIF(o.e2e_target_days, 0)) AS v_ratio,
               COALESCE(o.due_at, o.e2e_due_at) AS v_sort_due,
               CASE o.overall_state WHEN 'Breached' THEN 0 WHEN 'AtRisk' THEN 1 WHEN 'OnTrack' THEN 2 ELSE 3 END AS v_rank,
               CASE o.stage WHEN 'Submitted' THEN 0 WHEN 'InAssessment' THEN 1 ELSE 2 END AS v_stage_rank,
               cr.submitted_at AS v_submitted,
               COUNT(*) OVER()::BIGINT AS v_total
        FROM fn_sla_open_status() o
        JOIN change_request cr ON cr.id = o.change_request_id
        WHERE (p_stage IS NULL OR o.stage = p_stage)
          AND (p_change_type IS NULL OR cr.change_type = p_change_type)
          AND (p_state IS NULL OR o.overall_state = p_state)
          AND (v_search IS NULL
               OR position(v_search IN lower(cr.title)) > 0
               OR position(v_search IN lower(cr.request_number)) > 0)
    ) v
    ORDER BY CASE WHEN v_key = 'requestNumber' AND v_asc THEN v.v_number END ASC,
             CASE WHEN v_key = 'requestNumber' AND NOT v_asc THEN v.v_number END DESC,
             CASE WHEN v_key = 'title' AND v_asc THEN v.v_title END ASC,
             CASE WHEN v_key = 'title' AND NOT v_asc THEN v.v_title END DESC,
             CASE WHEN v_key = 'changeType' AND v_asc THEN v.v_type END ASC,
             CASE WHEN v_key = 'changeType' AND NOT v_asc THEN v.v_type END DESC,
             CASE WHEN v_key = 'stage' AND v_asc THEN v.v_stage_rank END ASC,
             CASE WHEN v_key = 'stage' AND NOT v_asc THEN v.v_stage_rank END DESC,
             CASE WHEN v_key = 'progress' AND v_asc THEN v.v_ratio END ASC NULLS LAST,
             CASE WHEN v_key = 'progress' AND NOT v_asc THEN v.v_ratio END DESC NULLS LAST,
             CASE WHEN v_key = 'dueAt' AND v_asc THEN v.v_sort_due END ASC NULLS LAST,
             CASE WHEN v_key = 'dueAt' AND NOT v_asc THEN v.v_sort_due END DESC NULLS LAST,
             CASE WHEN v_key = 'urgency' THEN v.v_rank END ASC,
             CASE WHEN v_key = 'urgency' THEN v.v_overdue END DESC,
             CASE WHEN v_key = 'urgency' THEN v.v_ratio END DESC NULLS LAST,
             v.v_submitted, v.v_cr
    LIMIT v_size OFFSET (v_page - 1) * v_size;
END;
$$;


--
-- Name: func_getuserbyauth0subject(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_getuserbyauth0subject(p_auth0_subject text) RETURNS TABLE(id uuid, display_name text, email text, roles text[])
    LANGUAGE sql STABLE
    AS $$
    SELECT u.id, u.display_name, u.email, array_agg(ur.role ORDER BY ur.role)
    FROM app_user u
    JOIN app_user_role ur ON ur.user_id = u.id
    WHERE u.auth0_subject = p_auth0_subject
      AND u.is_active = true
    GROUP BY u.id, u.display_name, u.email;
$$;


--
-- Name: func_getuserbyid(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_getuserbyid(p_id uuid) RETURNS TABLE(id uuid, display_name text, email text, roles text[])
    LANGUAGE sql STABLE
    AS $$
    SELECT u.id, u.display_name, u.email, array_agg(ur.role ORDER BY ur.role)
    FROM app_user u
    JOIN app_user_role ur ON ur.user_id = u.id
    WHERE u.id = p_id
      AND u.is_active = true
    GROUP BY u.id, u.display_name, u.email;
$$;


--
-- Name: func_getuserrole(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_getuserrole(p_user_id uuid) RETURNS text
    LANGUAGE sql STABLE
    AS $$
    SELECT role FROM app_user WHERE id = p_user_id AND is_active = true;
$$;


--
-- Name: func_getvendorbyid(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_getvendorbyid(p_id uuid) RETURNS TABLE(id uuid, vendor_name text, vendor_risk_rating text, vendor_jurisdiction text, data_access_scope text, certification_status text, updated_risk_rating text)
    LANGUAGE sql
    AS $$
    SELECT id, vendor_name, vendor_risk_rating, vendor_jurisdiction, data_access_scope, certification_status, updated_risk_rating
    FROM mock_systems.vendor_registry
    WHERE id = p_id;
$$;


--
-- Name: func_getworkflowrule(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_getworkflowrule(p_rule_key text) RETURNS TABLE(id uuid, rule_key text, rule_value_json jsonb, is_active boolean, created_at timestamp with time zone)
    LANGUAGE sql STABLE
    AS $$
    SELECT id, rule_key, rule_value, is_active, created_at
    FROM workflow_rule WHERE rule_key = p_rule_key AND is_active = true;
$$;


--
-- Name: func_linkuserauth0byemail(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_linkuserauth0byemail(p_email text, p_auth0_subject text) RETURNS TABLE(id uuid, display_name text, email text, roles text[])
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_user_id UUID;
BEGIN
    SELECT u.id INTO v_user_id
    FROM app_user u
    WHERE lower(u.email) = lower(p_email)
      AND u.auth0_subject IS NULL
      AND u.is_active = true;

    IF v_user_id IS NULL THEN
        RETURN;
    END IF;

    UPDATE app_user SET auth0_subject = p_auth0_subject WHERE id = v_user_id;

    INSERT INTO audit_event (entity_type, entity_id, action, actor_label, after_value, reason)
    VALUES ('AppUser', v_user_id, 'Auth0SubjectLinked', 'system',
            jsonb_build_object('auth0Subject', p_auth0_subject),
            'Auto-linked via verified email match on first login');

    RETURN QUERY
    SELECT u.id, u.display_name, u.email, array_agg(ur.role ORDER BY ur.role)
    FROM app_user u
    JOIN app_user_role ur ON ur.user_id = u.id
    WHERE u.id = v_user_id
    GROUP BY u.id, u.display_name, u.email;
END;
$$;


--
-- Name: func_listcustomers(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_listcustomers() RETURNS TABLE(id uuid, customer_name text, customer_type text, customer_geography text, segment_classification text, kyc_status text, risk_flag text)
    LANGUAGE sql
    AS $$
    SELECT id, customer_name, customer_type, customer_geography, segment_classification, kyc_status, risk_flag
    FROM mock_systems.crm_customer
    ORDER BY customer_name;
$$;


--
-- Name: func_listproducts(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_listproducts() RETURNS TABLE(id uuid, product_name text, product_type text, features_json jsonb, product_geography text, launch_change_type text, go_live_flag boolean, risk_rating text)
    LANGUAGE sql
    AS $$
    SELECT id, product_name, product_type, features_json, product_geography, launch_change_type, go_live_flag, risk_rating
    FROM mock_systems.core_banking_product
    ORDER BY product_name;
$$;


--
-- Name: func_listvendors(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_listvendors() RETURNS TABLE(id uuid, vendor_name text, vendor_risk_rating text, vendor_jurisdiction text, data_access_scope text, certification_status text, updated_risk_rating text)
    LANGUAGE sql
    AS $$
    SELECT id, vendor_name, vendor_risk_rating, vendor_jurisdiction, data_access_scope, certification_status, updated_risk_rating
    FROM mock_systems.vendor_registry
    ORDER BY vendor_name;
$$;


--
-- Name: func_overridecategorymapping(uuid, uuid, boolean, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_overridecategorymapping(p_assessment_id uuid, p_risk_category_id uuid, p_is_active boolean, p_reason text, p_actor_user_id uuid) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id UUID;
    v_before JSONB;
BEGIN
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'A reason is required to override a category mapping';
    END IF;

    SELECT to_jsonb(m) INTO v_before FROM assessment_category_mapping m
        WHERE assessment_id = p_assessment_id AND risk_category_id = p_risk_category_id;

    INSERT INTO assessment_category_mapping (assessment_id, risk_category_id, source, is_active, created_by_user_id)
    VALUES (p_assessment_id, p_risk_category_id, 'AnalystAdded', p_is_active, p_actor_user_id)
    ON CONFLICT (assessment_id, risk_category_id)
        DO UPDATE SET is_active = p_is_active, created_by_user_id = p_actor_user_id
    RETURNING id INTO v_id;

    INSERT INTO audit_event (assessment_id, entity_type, entity_id, action, actor_user_id, actor_label, before_value, after_value, reason)
    VALUES (p_assessment_id, 'CategoryMapping', v_id, 'Overridden', p_actor_user_id, 'human',
            v_before, jsonb_build_object('riskCategoryId', p_risk_category_id, 'isActive', p_is_active), p_reason);

    RETURN v_id;
END;
$$;


--
-- Name: func_overrideriskscore(uuid, uuid, numeric, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_overrideriskscore(p_assessment_id uuid, p_risk_category_id uuid, p_new_residual_rating numeric, p_reason text, p_actor_user_id uuid) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id UUID;
    v_before JSONB;
BEGIN
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'A reason is required to override a risk score';
    END IF;
    IF p_new_residual_rating <= 0 THEN
        RAISE EXCEPTION 'residual_rating must be greater than zero - controls mitigate risk, they never eliminate it';
    END IF;

    SELECT to_jsonb(s) INTO v_before FROM assessment_risk_score s
        WHERE assessment_id = p_assessment_id AND risk_category_id = p_risk_category_id;

    -- DEF-014: scored_by stayed 'System' after an override - the row IS the analyst's judgment
    -- now, and the UI/audit trail should say so, not attribute it to the original calculation.
    UPDATE assessment_risk_score
    SET residual_rating = p_new_residual_rating, is_override = true, override_reason = p_reason, scored_by = 'Analyst'
    WHERE assessment_id = p_assessment_id AND risk_category_id = p_risk_category_id
    RETURNING id INTO v_id;

    INSERT INTO audit_event (assessment_id, entity_type, entity_id, action, actor_user_id, actor_label, before_value, after_value, reason)
    VALUES (p_assessment_id, 'RiskScore', v_id, 'Overridden', p_actor_user_id, 'human',
            v_before, jsonb_build_object('riskCategoryId', p_risk_category_id, 'residual', p_new_residual_rating), p_reason);

    RETURN v_id;
END;
$$;


--
-- Name: func_recordcommitteedecision(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_recordcommitteedecision(p_assessment_id uuid, p_resolution text, p_conditions_text text) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: func_recordpolicyreliance(uuid, uuid, uuid, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_recordpolicyreliance(p_assessment_id uuid, p_risk_category_id uuid, p_policy_chunk_id uuid, p_decision text, p_decided_by_user_id uuid) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id UUID;
BEGIN
    -- DEF-011: the same passage relied upon for a second category used to hit the old
    -- (assessment_id, policy_chunk_id) conflict target and overwrite the first category's
    -- decision. risk_category_id is now part of the key (schema/007_policy_corpus.sql).
    INSERT INTO assessment_policy_reliance (assessment_id, risk_category_id, policy_chunk_id, decision, decided_by_user_id)
    VALUES (p_assessment_id, p_risk_category_id, p_policy_chunk_id, p_decision, p_decided_by_user_id)
    ON CONFLICT (assessment_id, risk_category_id, policy_chunk_id)
        DO UPDATE SET decision = EXCLUDED.decision, decided_by_user_id = EXCLUDED.decided_by_user_id, decided_at = now()
    RETURNING id INTO v_id;

    INSERT INTO audit_event (assessment_id, entity_type, entity_id, action, actor_user_id, actor_label, after_value)
    VALUES (p_assessment_id, 'PolicyReliance', v_id, 'Decided', p_decided_by_user_id, 'human',
            jsonb_build_object('policyChunkId', p_policy_chunk_id, 'decision', p_decision));

    RETURN v_id;
END;
$$;


--
-- Name: func_removeslaholiday(uuid, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_removeslaholiday(p_holiday_id uuid, p_reason text, p_actor_user_id uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_date DATE;
BEGIN
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'A reason is required to change the holiday calendar';
    END IF;

    UPDATE sla_holiday SET is_active = false
    WHERE id = p_holiday_id AND is_active
    RETURNING holiday_date INTO v_date;
    IF v_date IS NULL THEN
        RAISE EXCEPTION 'That holiday is not on the calendar';
    END IF;

    INSERT INTO audit_event (entity_type, entity_id, action, actor_user_id, actor_label, before_value, reason)
    VALUES ('SlaHoliday', p_holiday_id, 'ConfigChanged', p_actor_user_id, 'human',
            jsonb_build_object('holidayDate', to_char(v_date, 'YYYY-MM-DD'), 'change', 'Removed'), p_reason);
END;
$$;


--
-- Name: func_requestclarification(uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_requestclarification(p_change_request_id uuid, p_requested_by_user_id uuid, p_question text) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: func_reviewnarrativesection(uuid, uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_reviewnarrativesection(p_assessment_id uuid, p_risk_category_id uuid, p_actor_user_id uuid) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id UUID;
BEGIN
    UPDATE assessment_narrative_section
    SET status = 'AnalystReviewed', updated_by_user_id = p_actor_user_id, updated_at = now()
    WHERE assessment_id = p_assessment_id AND risk_category_id = p_risk_category_id
    RETURNING id INTO v_id;

    INSERT INTO audit_event (assessment_id, entity_type, entity_id, action, actor_user_id, actor_label, after_value)
    VALUES (p_assessment_id, 'NarrativeSection', v_id, 'AnalystReviewed', p_actor_user_id, 'human',
            jsonb_build_object('riskCategoryId', p_risk_category_id, 'status', 'AnalystReviewed'));

    RETURN v_id;
END;
$$;


--
-- Name: func_routetocommittee(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_routetocommittee(p_assessment_id uuid, p_actor_user_id uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: func_savecategorymappingproposal(uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_savecategorymappingproposal(p_assessment_id uuid, p_risk_category_id uuid, p_ai_citation text) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id UUID;
BEGIN
    INSERT INTO assessment_category_mapping (assessment_id, risk_category_id, source, ai_citation)
    VALUES (p_assessment_id, p_risk_category_id, 'AiProposed', p_ai_citation)
    ON CONFLICT (assessment_id, risk_category_id) DO UPDATE SET ai_citation = EXCLUDED.ai_citation
    RETURNING id INTO v_id;

    INSERT INTO audit_event (assessment_id, entity_type, entity_id, action, actor_label, after_value)
    VALUES (p_assessment_id, 'CategoryMapping', v_id, 'AiProposed', 'system/AI',
            jsonb_build_object('riskCategoryId', p_risk_category_id, 'citation', p_ai_citation));

    RETURN v_id;
END;
$$;


--
-- Name: func_saveexternalsnapshot(uuid, uuid, jsonb, uuid, jsonb, uuid, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_saveexternalsnapshot(p_change_request_id uuid, p_mock_customer_id uuid, p_customer_risk_context jsonb, p_mock_product_id uuid, p_product_risk_context jsonb, p_mock_vendor_id uuid, p_vendor_risk_context jsonb) RETURNS TABLE(id uuid, ingested_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO change_request_external_snapshot (
        change_request_id, mock_customer_id, customer_risk_context,
        mock_product_id, product_risk_context, mock_vendor_id, vendor_risk_context
    ) VALUES (
        p_change_request_id, p_mock_customer_id, p_customer_risk_context,
        p_mock_product_id, p_product_risk_context, p_mock_vendor_id, p_vendor_risk_context
    )
    ON CONFLICT (change_request_id) DO NOTHING; -- immutable: never overwrite an existing snapshot

    INSERT INTO audit_event (change_request_id, entity_type, entity_id, action, actor_label, after_value)
    VALUES (p_change_request_id, 'ExternalSnapshot', p_change_request_id, 'Ingested', 'system',
            jsonb_build_object(
                'hasCustomer', p_mock_customer_id IS NOT NULL,
                'hasProduct', p_mock_product_id IS NOT NULL,
                'hasVendor', p_mock_vendor_id IS NOT NULL));

    RETURN QUERY SELECT s.id, s.ingested_at FROM change_request_external_snapshot s WHERE s.change_request_id = p_change_request_id;
END;
$$;


--
-- Name: func_saveextractedfield(uuid, uuid, text, text, numeric, boolean, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_saveextractedfield(p_change_request_id uuid, p_attachment_id uuid, p_field_key text, p_field_value text, p_confidence numeric, p_needs_review boolean, p_source_excerpt text) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id UUID;
BEGIN
    INSERT INTO extracted_field (change_request_id, attachment_id, field_key, field_value, confidence, needs_review, source_excerpt, source)
    VALUES (p_change_request_id, p_attachment_id, p_field_key, p_field_value, p_confidence, p_needs_review, p_source_excerpt, 'AiExtracted')
    ON CONFLICT (change_request_id, field_key) DO UPDATE SET
        field_value = EXCLUDED.field_value, confidence = EXCLUDED.confidence,
        needs_review = EXCLUDED.needs_review, source_excerpt = EXCLUDED.source_excerpt,
        source = 'AiExtracted', updated_at = now()
    RETURNING id INTO v_id;

    INSERT INTO audit_event (change_request_id, entity_type, entity_id, action, actor_label, after_value)
    VALUES (p_change_request_id, 'ExtractedField', v_id, 'AiExtracted', 'system/AI',
            jsonb_build_object('fieldKey', p_field_key, 'value', p_field_value, 'confidence', p_confidence, 'needsReview', p_needs_review));

    RETURN v_id;
END;
$$;


--
-- Name: func_savenarrativesection(uuid, uuid, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_savenarrativesection(p_assessment_id uuid, p_risk_category_id uuid, p_narrative_text text, p_unsupported_claim_flags jsonb) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id UUID;
    v_before JSONB;
BEGIN
    SELECT to_jsonb(s) INTO v_before FROM assessment_narrative_section s
        WHERE assessment_id = p_assessment_id AND risk_category_id = p_risk_category_id;

    INSERT INTO assessment_narrative_section (assessment_id, risk_category_id, narrative_text, unsupported_claim_flags, status)
    VALUES (p_assessment_id, p_risk_category_id, p_narrative_text, COALESCE(p_unsupported_claim_flags, '[]'::jsonb), 'AiDrafted')
    ON CONFLICT (assessment_id, risk_category_id) DO UPDATE SET
        narrative_text = EXCLUDED.narrative_text, unsupported_claim_flags = EXCLUDED.unsupported_claim_flags,
        status = 'AiDrafted', updated_by_user_id = NULL, updated_at = now()
    RETURNING id INTO v_id;

    INSERT INTO audit_event (assessment_id, entity_type, entity_id, action, actor_label, before_value, after_value)
    VALUES (p_assessment_id, 'NarrativeSection', v_id, 'AiDrafted', 'system/AI',
            v_before, jsonb_build_object('riskCategoryId', p_risk_category_id, 'text', p_narrative_text));

    RETURN v_id;
END;
$$;


--
-- Name: func_searchpolicychunks(text, uuid, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_searchpolicychunks(p_query_text text, p_risk_category_id uuid DEFAULT NULL::uuid, p_top_k integer DEFAULT 5) RETURNS TABLE(id uuid, policy_document_id uuid, document_title text, source_url text, effective_date date, section_ref text, chunk_text text, rank real)
    LANGUAGE sql STABLE
    AS $$
    SELECT pc.id, pc.policy_document_id, pd.title, pd.source_url, pd.effective_date, pc.section_ref, pc.chunk_text,
           ts_rank(pc.search_vector, plainto_tsquery('english', p_query_text)) AS rank
    FROM policy_chunk pc
    JOIN policy_document pd ON pd.id = pc.policy_document_id
    WHERE (p_risk_category_id IS NULL OR pc.risk_category_id = p_risk_category_id)
      AND pc.search_vector @@ plainto_tsquery('english', p_query_text)
    ORDER BY rank DESC
    LIMIT p_top_k;
$$;


--
-- Name: func_setuseractive(uuid, boolean, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_setuseractive(p_user_id uuid, p_is_active boolean, p_reason text, p_actor_user_id uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_before BOOLEAN;
BEGIN
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'A reason is required to deactivate or reactivate a user';
    END IF;

    SELECT is_active INTO v_before FROM app_user WHERE id = p_user_id;
    IF v_before IS NULL THEN
        RAISE EXCEPTION 'User % not found', p_user_id;
    END IF;

    -- Guard against the last active Admin locking everyone out: deactivating would leave no one
    -- able to manage users/configuration without going straight to SQL.
    IF p_is_active = FALSE AND EXISTS (
        SELECT 1 FROM app_user_role WHERE user_id = p_user_id AND role = 'Admin'
    ) AND NOT EXISTS (
        SELECT 1
        FROM app_user_role r
        JOIN app_user u ON u.id = r.user_id
        WHERE r.role = 'Admin' AND u.is_active = TRUE AND u.id <> p_user_id
    ) THEN
        RAISE EXCEPTION 'Cannot deactivate the last active Admin';
    END IF;

    UPDATE app_user SET is_active = p_is_active WHERE id = p_user_id;

    INSERT INTO audit_event (entity_type, entity_id, action, actor_user_id, actor_label, before_value, after_value, reason)
    VALUES ('AppUser', p_user_id, CASE WHEN p_is_active THEN 'Reactivated' ELSE 'Deactivated' END,
            p_actor_user_id, 'human', jsonb_build_object('isActive', v_before), jsonb_build_object('isActive', p_is_active), p_reason);
END;
$$;


--
-- Name: func_setuserauth0subject(uuid, text, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_setuserauth0subject(p_user_id uuid, p_auth0_subject text, p_reason text, p_actor_user_id uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_before TEXT;
BEGIN
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'A reason is required to link an Auth0 login';
    END IF;
    IF p_auth0_subject IS NULL OR btrim(p_auth0_subject) = '' THEN
        RAISE EXCEPTION 'An Auth0 subject is required';
    END IF;

    SELECT auth0_subject INTO v_before FROM app_user WHERE id = p_user_id;

    UPDATE app_user SET auth0_subject = p_auth0_subject WHERE id = p_user_id;

    INSERT INTO audit_event (entity_type, entity_id, action, actor_user_id, actor_label, before_value, after_value, reason)
    VALUES ('AppUser', p_user_id, 'Auth0SubjectLinked', p_actor_user_id, 'human',
            jsonb_build_object('auth0Subject', v_before), jsonb_build_object('auth0Subject', p_auth0_subject), p_reason);
END;
$$;


--
-- Name: func_setuserroles(uuid, text[], text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_setuserroles(p_user_id uuid, p_roles text[], p_reason text, p_actor_user_id uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_before TEXT[];
    v_role TEXT;
BEGIN
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'A reason is required to change a user''s roles';
    END IF;
    IF p_roles IS NULL OR array_length(p_roles, 1) IS NULL THEN
        RAISE EXCEPTION 'A user must hold at least one role';
    END IF;

    SELECT array_agg(role ORDER BY role) INTO v_before FROM app_user_role WHERE user_id = p_user_id;

    -- Guard against stripping the last active Admin's Admin role: would leave no one able to
    -- manage users/configuration without going straight to SQL.
    IF 'Admin' = ANY(v_before) AND NOT ('Admin' = ANY(p_roles)) AND NOT EXISTS (
        SELECT 1
        FROM app_user_role r
        JOIN app_user u ON u.id = r.user_id
        WHERE r.role = 'Admin' AND u.is_active = TRUE AND u.id <> p_user_id
    ) THEN
        RAISE EXCEPTION 'Cannot remove the Admin role from the last active Admin';
    END IF;

    DELETE FROM app_user_role WHERE user_id = p_user_id AND role NOT IN (SELECT unnest(p_roles));

    FOREACH v_role IN ARRAY p_roles LOOP
        INSERT INTO app_user_role (user_id, role, granted_by_user_id, reason)
        VALUES (p_user_id, v_role, p_actor_user_id, p_reason)
        ON CONFLICT (user_id, role) DO NOTHING;
    END LOOP;

    INSERT INTO audit_event (entity_type, entity_id, action, actor_user_id, actor_label, before_value, after_value, reason)
    VALUES ('AppUser', p_user_id, 'RolesChanged', p_actor_user_id, 'human',
            jsonb_build_object('roles', v_before), jsonb_build_object('roles', p_roles), p_reason);
END;
$$;


--
-- Name: func_updatechangerequeststatus(uuid, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_updatechangerequeststatus(p_change_request_id uuid, p_new_status text, p_actor_user_id uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_old_status TEXT;
BEGIN
    SELECT status INTO v_old_status FROM change_request WHERE id = p_change_request_id;

    UPDATE change_request SET status = p_new_status WHERE id = p_change_request_id;

    INSERT INTO audit_event (change_request_id, entity_type, entity_id, action, actor_user_id, actor_label, before_value, after_value)
    VALUES (p_change_request_id, 'ChangeRequest', p_change_request_id, 'StatusChanged', p_actor_user_id,
            CASE WHEN p_actor_user_id IS NULL THEN 'system/AI' ELSE 'human' END,
            jsonb_build_object('status', v_old_status), jsonb_build_object('status', p_new_status));
END;
$$;


--
-- Name: func_updatecustomerriskflag(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_updatecustomerriskflag(p_id uuid, p_risk_flag text) RETURNS TABLE(id uuid)
    LANGUAGE sql
    AS $$
    UPDATE mock_systems.crm_customer
    SET risk_flag = p_risk_flag
    WHERE id = p_id
    RETURNING id;
$$;


--
-- Name: func_updateproductriskrating(uuid, boolean, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_updateproductriskrating(p_id uuid, p_go_live boolean, p_risk_rating text) RETURNS TABLE(id uuid)
    LANGUAGE sql
    AS $$
    UPDATE mock_systems.core_banking_product
    SET go_live_flag = p_go_live, risk_rating = p_risk_rating
    WHERE id = p_id
    RETURNING id;
$$;


--
-- Name: func_updatevendorriskrating(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_updatevendorriskrating(p_id uuid, p_updated_risk_rating text) RETURNS TABLE(id uuid)
    LANGUAGE sql
    AS $$
    UPDATE mock_systems.vendor_registry
    SET updated_risk_rating = p_updated_risk_rating
    WHERE id = p_id
    RETURNING id;
$$;


--
-- Name: func_upsertscoringconfig(uuid, numeric, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_upsertscoringconfig(p_risk_category_id uuid, p_max_mitigation_factor numeric, p_reason text, p_actor_user_id uuid) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id UUID := gen_random_uuid();
BEGIN
    IF p_max_mitigation_factor >= 1.0 OR p_max_mitigation_factor < 0 THEN
        RAISE EXCEPTION 'max_mitigation_factor must be in [0, 1.0) - a value of 1.0 or more would let residual risk reach zero';
    END IF;
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'A reason is required to change a scoring configuration';
    END IF;

    UPDATE scoring_config SET is_active = false WHERE risk_category_id = p_risk_category_id AND is_active = true;

    INSERT INTO scoring_config (id, risk_category_id, max_mitigation_factor, created_by_user_id, reason)
    VALUES (v_id, p_risk_category_id, p_max_mitigation_factor, p_actor_user_id, p_reason);

    INSERT INTO audit_event (entity_type, entity_id, action, actor_user_id, actor_label, after_value, reason)
    VALUES ('ScoringConfig', v_id, 'ConfigChanged', p_actor_user_id, 'human',
            jsonb_build_object('riskCategoryId', p_risk_category_id, 'maxMitigationFactor', p_max_mitigation_factor), p_reason);

    RETURN v_id;
END;
$$;


--
-- Name: func_upsertslaconfig(jsonb, integer, boolean, boolean, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_upsertslaconfig(p_targets jsonb, p_at_risk_threshold_pct integer, p_pause_on_clarification boolean, p_retroactive boolean, p_reason text, p_actor_user_id uuid) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id UUID := gen_random_uuid();
    v_version INT;
    v_entry JSONB;
    v_seen TEXT[] := ARRAY[]::TEXT[];
    v_key TEXT;
    v_type TEXT;
    v_days NUMERIC;
    v_before JSONB;
BEGIN
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'A reason is required to change the SLA configuration';
    END IF;
    IF p_at_risk_threshold_pct IS NULL OR p_at_risk_threshold_pct < 1 OR p_at_risk_threshold_pct > 99 THEN
        RAISE EXCEPTION 'The at-risk warning threshold must be a whole number between 1 and 99 (percent of the target)';
    END IF;
    IF p_targets IS NULL OR jsonb_typeof(p_targets) <> 'array' THEN
        RAISE EXCEPTION 'SLA targets must be a list of change type / stage targets';
    END IF;

    FOR v_entry IN SELECT * FROM jsonb_array_elements(p_targets) LOOP
        v_key := (v_entry->>'changeType') || '/' || (v_entry->>'stage');
        IF (v_entry->>'changeType') IS NULL OR (v_entry->>'changeType') NOT IN ('Product','Feature','Process','Vendor','Geography','CustomerSegment') THEN
            RAISE EXCEPTION 'Unknown change type in SLA targets: %', COALESCE(v_entry->>'changeType', '(blank)');
        END IF;
        IF (v_entry->>'stage') IS NULL OR (v_entry->>'stage') NOT IN ('Submitted','InAssessment','PendingCommittee','EndToEnd') THEN
            RAISE EXCEPTION 'Unknown stage in SLA targets: %', COALESCE(v_entry->>'stage', '(blank)');
        END IF;
        IF jsonb_typeof(v_entry->'targetBusinessDays') IS DISTINCT FROM 'number' THEN
            RAISE EXCEPTION 'The % target must be a whole number of business days greater than zero', v_key;
        END IF;
        v_days := (v_entry->>'targetBusinessDays')::NUMERIC;
        IF v_days <= 0 OR v_days <> trunc(v_days) THEN
            RAISE EXCEPTION 'The % target must be a whole number of business days greater than zero', v_key;
        END IF;
        IF v_key = ANY (v_seen) THEN
            RAISE EXCEPTION 'The % target was given more than once', v_key;
        END IF;
        v_seen := v_seen || v_key;
    END LOOP;

    FOREACH v_type IN ARRAY ARRAY['Product','Feature','Process','Vendor','Geography','CustomerSegment'] LOOP
        IF NOT ((v_type || '/EndToEnd') = ANY (v_seen)) THEN
            RAISE EXCEPTION 'An overall (start to decision) target is required for %', v_type;
        END IF;
    END LOOP;

    SELECT jsonb_build_object(
               'version', c.version_number,
               'atRiskThresholdPct', c.at_risk_threshold_pct,
               'pauseOnClarification', c.pause_on_clarification,
               'targets', (SELECT jsonb_agg(jsonb_build_object('changeType', t.change_type, 'stage', t.stage, 'targetBusinessDays', t.target_business_days)
                                            ORDER BY t.change_type, t.stage)
                           FROM sla_target t WHERE t.sla_config_id = c.id))
    INTO v_before
    FROM sla_config c WHERE c.is_active;

    SELECT COALESCE(MAX(version_number), 0) + 1 INTO v_version FROM sla_config;
    UPDATE sla_config SET is_active = false WHERE is_active;

    INSERT INTO sla_config (id, version_number, at_risk_threshold_pct, pause_on_clarification, created_by_user_id, reason)
    VALUES (v_id, v_version, p_at_risk_threshold_pct, COALESCE(p_pause_on_clarification, true), p_actor_user_id, p_reason);

    INSERT INTO sla_target (sla_config_id, change_type, stage, target_business_days)
    SELECT v_id, e->>'changeType', e->>'stage', (e->>'targetBusinessDays')::INT
    FROM jsonb_array_elements(p_targets) e;

    IF COALESCE(p_retroactive, false) THEN
        UPDATE change_request_sla s SET sla_config_id = v_id
        FROM change_request cr
        WHERE cr.id = s.change_request_id AND cr.status <> 'Decisioned';

        -- A stage with no target in the new version ends up with no target (null), not its old one.
        UPDATE change_request_stage_history h
        SET target_business_days = (
            SELECT t.target_business_days
            FROM change_request cr
            JOIN sla_target t ON t.change_type = cr.change_type AND t.stage = h.stage
            WHERE cr.id = h.change_request_id AND t.sla_config_id = v_id)
        WHERE h.left_at IS NULL;
    END IF;

    INSERT INTO audit_event (entity_type, entity_id, action, actor_user_id, actor_label, before_value, after_value, reason)
    VALUES ('SlaConfig', v_id, 'ConfigChanged', p_actor_user_id, 'human', v_before,
            jsonb_build_object('version', v_version,
                               'atRiskThresholdPct', p_at_risk_threshold_pct,
                               'pauseOnClarification', COALESCE(p_pause_on_clarification, true),
                               'retroactive', COALESCE(p_retroactive, false),
                               'targets', p_targets),
            p_reason);

    RETURN v_id;
END;
$$;


--
-- Name: func_upsertworkflowrule(text, jsonb, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_upsertworkflowrule(p_rule_key text, p_rule_value jsonb, p_reason text, p_actor_user_id uuid) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id UUID := gen_random_uuid();
BEGIN
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'A reason is required to change a workflow rule';
    END IF;

    UPDATE workflow_rule SET is_active = false WHERE rule_key = p_rule_key AND is_active = true;

    INSERT INTO workflow_rule (id, rule_key, rule_value, created_by_user_id, reason)
    VALUES (v_id, p_rule_key, p_rule_value, p_actor_user_id, p_reason);

    INSERT INTO audit_event (entity_type, entity_id, action, actor_user_id, actor_label, after_value, reason)
    VALUES ('WorkflowRule', v_id, 'ConfigChanged', p_actor_user_id, 'human',
            jsonb_build_object('ruleKey', p_rule_key, 'ruleValue', p_rule_value), p_reason);

    RETURN v_id;
END;
$$;


--
-- Name: func_userhasrole(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.func_userhasrole(p_user_id uuid, p_role text) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
    SELECT EXISTS (
        SELECT 1
        FROM app_user u
        JOIN app_user_role ur ON ur.user_id = u.id
        WHERE u.id = p_user_id
          AND u.is_active = true
          AND ur.role = p_role
    );
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: core_banking_product; Type: TABLE; Schema: mock_systems; Owner: -
--

CREATE TABLE mock_systems.core_banking_product (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    product_name text NOT NULL,
    product_type text NOT NULL,
    features_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    product_geography text NOT NULL,
    launch_change_type text NOT NULL,
    go_live_flag boolean,
    risk_rating text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT core_banking_product_launch_change_type_check CHECK ((launch_change_type = ANY (ARRAY['New'::text, 'FeatureAdd'::text, 'ProcessChange'::text])))
);


--
-- Name: crm_customer; Type: TABLE; Schema: mock_systems; Owner: -
--

CREATE TABLE mock_systems.crm_customer (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    customer_name text NOT NULL,
    customer_type text NOT NULL,
    customer_geography text NOT NULL,
    segment_classification text NOT NULL,
    kyc_status text NOT NULL,
    risk_flag text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT crm_customer_customer_type_check CHECK ((customer_type = ANY (ARRAY['Individual'::text, 'SmallBusiness'::text, 'Corporate'::text, 'MSB'::text, 'NGO'::text]))),
    CONSTRAINT crm_customer_kyc_status_check CHECK ((kyc_status = ANY (ARRAY['Verified'::text, 'Pending'::text, 'Flagged'::text]))),
    CONSTRAINT crm_customer_segment_classification_check CHECK ((segment_classification = ANY (ARRAY['Retail'::text, 'PrivateBanking'::text, 'Commercial'::text])))
);


--
-- Name: vendor_registry; Type: TABLE; Schema: mock_systems; Owner: -
--

CREATE TABLE mock_systems.vendor_registry (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    vendor_name text NOT NULL,
    vendor_risk_rating text NOT NULL,
    vendor_jurisdiction text NOT NULL,
    data_access_scope text NOT NULL,
    certification_status text NOT NULL,
    updated_risk_rating text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT vendor_registry_certification_status_check CHECK ((certification_status = ANY (ARRAY['Certified'::text, 'Pending'::text, 'None'::text]))),
    CONSTRAINT vendor_registry_vendor_risk_rating_check CHECK ((vendor_risk_rating = ANY (ARRAY['Low'::text, 'Medium'::text, 'High'::text])))
);


--
-- Name: app_user; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.app_user (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    auth0_subject text,
    email text NOT NULL,
    display_name text NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: app_user_role; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.app_user_role (
    user_id uuid NOT NULL,
    role text NOT NULL,
    granted_by_user_id uuid,
    reason text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT app_user_role_role_check CHECK ((role = ANY (ARRAY['ProductOwner'::text, 'Analyst'::text, 'CommitteeMember'::text, 'Admin'::text])))
);


--
-- Name: assessment; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.assessment (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    change_request_id uuid NOT NULL,
    status text DEFAULT 'Draft'::text NOT NULL,
    finalized_by_user_id uuid,
    finalized_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT assessment_status_check CHECK ((status = ANY (ARRAY['Draft'::text, 'Finalized'::text])))
);


--
-- Name: assessment_category_mapping; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.assessment_category_mapping (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    assessment_id uuid NOT NULL,
    risk_category_id uuid NOT NULL,
    source text NOT NULL,
    ai_citation text,
    is_active boolean DEFAULT true NOT NULL,
    created_by_user_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT assessment_category_mapping_source_check CHECK ((source = ANY (ARRAY['AiProposed'::text, 'AnalystAdded'::text])))
);


--
-- Name: assessment_narrative_section; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.assessment_narrative_section (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    assessment_id uuid NOT NULL,
    risk_category_id uuid NOT NULL,
    narrative_text text NOT NULL,
    status text DEFAULT 'AiDrafted'::text NOT NULL,
    unsupported_claim_flags jsonb DEFAULT '[]'::jsonb NOT NULL,
    updated_by_user_id uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT assessment_narrative_section_status_check CHECK ((status = ANY (ARRAY['AiDrafted'::text, 'AnalystReviewed'::text, 'AnalystEdited'::text])))
);


--
-- Name: assessment_policy_reliance; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.assessment_policy_reliance (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    assessment_id uuid NOT NULL,
    risk_category_id uuid,
    policy_chunk_id uuid NOT NULL,
    decision text NOT NULL,
    decided_by_user_id uuid NOT NULL,
    decided_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT assessment_policy_reliance_decision_check CHECK ((decision = ANY (ARRAY['ReliedUpon'::text, 'NotRelevant'::text])))
);


--
-- Name: assessment_risk_score; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.assessment_risk_score (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    assessment_id uuid NOT NULL,
    risk_category_id uuid NOT NULL,
    inherent_rating numeric(5,2) NOT NULL,
    control_ids_credited jsonb DEFAULT '[]'::jsonb NOT NULL,
    control_effectiveness numeric(4,3) NOT NULL,
    mitigation_factor_applied numeric(4,3) NOT NULL,
    residual_rating numeric(5,2) NOT NULL,
    is_override boolean DEFAULT false NOT NULL,
    override_reason text,
    scored_by text NOT NULL,
    created_by_user_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT assessment_risk_score_check CHECK (((NOT is_override) OR (override_reason IS NOT NULL))),
    CONSTRAINT assessment_risk_score_control_effectiveness_check CHECK (((control_effectiveness >= (0)::numeric) AND (control_effectiveness <= (1)::numeric))),
    CONSTRAINT assessment_risk_score_inherent_rating_check CHECK (((inherent_rating >= (1)::numeric) AND (inherent_rating <= (5)::numeric))),
    CONSTRAINT assessment_risk_score_mitigation_factor_applied_check CHECK (((mitigation_factor_applied >= (0)::numeric) AND (mitigation_factor_applied < 1.0))),
    CONSTRAINT assessment_risk_score_residual_rating_check CHECK ((residual_rating > (0)::numeric)),
    CONSTRAINT assessment_risk_score_scored_by_check CHECK ((scored_by = ANY (ARRAY['System'::text, 'Analyst'::text])))
);


--
-- Name: audit_event; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_event (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    change_request_id uuid,
    assessment_id uuid,
    entity_type text NOT NULL,
    entity_id uuid,
    action text NOT NULL,
    actor_user_id uuid,
    actor_label text DEFAULT 'system/AI'::text NOT NULL,
    before_value jsonb,
    after_value jsonb,
    reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: change_request; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.change_request (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    request_number text NOT NULL,
    change_type text NOT NULL,
    title text NOT NULL,
    description text NOT NULL,
    type_specific_fields jsonb DEFAULT '{}'::jsonb NOT NULL,
    status text DEFAULT 'Submitted'::text NOT NULL,
    submitted_by_user_id uuid NOT NULL,
    submitted_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT change_request_change_type_check CHECK ((change_type = ANY (ARRAY['Product'::text, 'Feature'::text, 'Process'::text, 'Vendor'::text, 'Geography'::text, 'CustomerSegment'::text]))),
    CONSTRAINT change_request_status_check CHECK ((status = ANY (ARRAY['Submitted'::text, 'InAssessment'::text, 'PendingCommittee'::text, 'Decisioned'::text])))
);


--
-- Name: change_request_attachment; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.change_request_attachment (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    change_request_id uuid NOT NULL,
    file_name text NOT NULL,
    content_type text NOT NULL,
    storage_path text NOT NULL,
    extracted_text text,
    version_number integer DEFAULT 1 NOT NULL,
    superseded_by_attachment_id uuid,
    uploaded_by_user_id uuid NOT NULL,
    uploaded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT change_request_attachment_content_type_check CHECK ((content_type = ANY (ARRAY['application/pdf'::text, 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'::text, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'::text])))
);


--
-- Name: change_request_clarification; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.change_request_clarification (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    change_request_id uuid NOT NULL,
    requested_by_user_id uuid NOT NULL,
    question text NOT NULL,
    status text DEFAULT 'Open'::text NOT NULL,
    answer text,
    answered_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT change_request_clarification_status_check CHECK ((status = ANY (ARRAY['Open'::text, 'Answered'::text])))
);


--
-- Name: change_request_external_snapshot; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.change_request_external_snapshot (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    change_request_id uuid NOT NULL,
    mock_customer_id uuid,
    customer_risk_context jsonb,
    mock_product_id uuid,
    product_risk_context jsonb,
    mock_vendor_id uuid,
    vendor_risk_context jsonb,
    ingested_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: change_request_number_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.change_request_number_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: change_request_sla; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.change_request_sla (
    change_request_id uuid NOT NULL,
    sla_config_id uuid,
    decided_at timestamp with time zone,
    e2e_actual_business_days integer,
    e2e_met boolean
);


--
-- Name: change_request_stage_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.change_request_stage_history (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    change_request_id uuid NOT NULL,
    stage text NOT NULL,
    entered_at timestamp with time zone NOT NULL,
    left_at timestamp with time zone,
    target_business_days integer,
    actual_business_days integer,
    met_sla boolean,
    CONSTRAINT change_request_stage_history_stage_check CHECK ((stage = ANY (ARRAY['Submitted'::text, 'InAssessment'::text, 'PendingCommittee'::text])))
);


--
-- Name: change_request_type_category_map; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.change_request_type_category_map (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    change_type text NOT NULL,
    risk_category_id uuid NOT NULL,
    weight text NOT NULL,
    CONSTRAINT change_request_type_category_map_change_type_check CHECK ((change_type = ANY (ARRAY['Product'::text, 'Feature'::text, 'Process'::text, 'Vendor'::text, 'Geography'::text, 'CustomerSegment'::text]))),
    CONSTRAINT change_request_type_category_map_weight_check CHECK ((weight = ANY (ARRAY['Primary'::text, 'Secondary'::text])))
);


--
-- Name: committee_decision; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.committee_decision (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    assessment_id uuid NOT NULL,
    resolution text NOT NULL,
    conditions_text text,
    decided_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT committee_decision_resolution_check CHECK ((resolution = ANY (ARRAY['Approved'::text, 'Rejected'::text, 'Deferred'::text, 'ApprovedWithConditions'::text])))
);


--
-- Name: committee_vote; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.committee_vote (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    assessment_id uuid NOT NULL,
    committee_member_user_id uuid NOT NULL,
    vote text NOT NULL,
    conditions_text text,
    rationale text,
    voted_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT committee_vote_vote_check CHECK ((vote = ANY (ARRAY['Approve'::text, 'Reject'::text, 'Defer'::text, 'ApproveWithConditions'::text])))
);


--
-- Name: control; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.control (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    risk_category_id uuid,
    name text NOT NULL,
    description text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: extracted_field; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.extracted_field (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    change_request_id uuid NOT NULL,
    attachment_id uuid,
    field_key text NOT NULL,
    field_value text,
    confidence numeric(4,3),
    needs_review boolean DEFAULT false NOT NULL,
    source_excerpt text,
    source text NOT NULL,
    updated_by_user_id uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT extracted_field_source_check CHECK ((source = ANY (ARRAY['AiExtracted'::text, 'AnalystCorrected'::text])))
);


--
-- Name: policy_chunk; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.policy_chunk (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    policy_document_id uuid NOT NULL,
    risk_category_id uuid,
    section_ref text NOT NULL,
    chunk_text text NOT NULL,
    search_vector tsvector GENERATED ALWAYS AS (to_tsvector('english'::regconfig, chunk_text)) STORED,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: policy_document; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.policy_document (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    risk_framework_id uuid,
    title text NOT NULL,
    source_url text NOT NULL,
    effective_date date,
    version_label text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: risk_category; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.risk_category (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    risk_framework_id uuid NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    citation_section text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: risk_framework; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.risk_framework (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    citation_source text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: risk_subfactor; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.risk_subfactor (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    risk_category_id uuid NOT NULL,
    name text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    filename text NOT NULL,
    applied_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: scoring_config; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.scoring_config (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    risk_category_id uuid NOT NULL,
    max_mitigation_factor numeric(4,3) NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_by_user_id uuid NOT NULL,
    reason text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT scoring_config_max_mitigation_factor_check CHECK (((max_mitigation_factor >= (0)::numeric) AND (max_mitigation_factor < 1.0)))
);


--
-- Name: sla_config; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sla_config (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    version_number integer NOT NULL,
    at_risk_threshold_pct integer NOT NULL,
    pause_on_clarification boolean DEFAULT true NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_by_user_id uuid NOT NULL,
    reason text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT sla_config_at_risk_threshold_pct_check CHECK (((at_risk_threshold_pct >= 1) AND (at_risk_threshold_pct <= 99)))
);


--
-- Name: sla_holiday; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sla_holiday (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    holiday_date date NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_by_user_id uuid NOT NULL,
    reason text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: sla_target; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sla_target (
    sla_config_id uuid NOT NULL,
    change_type text NOT NULL,
    stage text NOT NULL,
    target_business_days integer NOT NULL,
    CONSTRAINT sla_target_change_type_check CHECK ((change_type = ANY (ARRAY['Product'::text, 'Feature'::text, 'Process'::text, 'Vendor'::text, 'Geography'::text, 'CustomerSegment'::text]))),
    CONSTRAINT sla_target_stage_check CHECK ((stage = ANY (ARRAY['Submitted'::text, 'InAssessment'::text, 'PendingCommittee'::text, 'EndToEnd'::text]))),
    CONSTRAINT sla_target_target_business_days_check CHECK ((target_business_days > 0))
);


--
-- Name: workflow_rule; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workflow_rule (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    rule_key text NOT NULL,
    rule_value jsonb NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_by_user_id uuid NOT NULL,
    reason text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Data for Name: core_banking_product; Type: TABLE DATA; Schema: mock_systems; Owner: -
--

COPY mock_systems.core_banking_product (id, product_name, product_type, features_json, product_geography, launch_change_type, go_live_flag, risk_rating, created_at) FROM stdin;
b2222222-0000-0000-0000-000000000001	Cross-Border Wire Transfer Plus	WireTransfer	{"channels": ["online", "branch"], "dailyLimitUsd": 500000}	Bangladesh	New	\N	\N	2026-09-22 14:00:37.236345+00
b2222222-0000-0000-0000-000000000002	Mobile App UI Refresh	ProcessChange	{"scope": "UI only, no new data flows"}	United States	ProcessChange	\N	\N	2026-09-22 14:00:37.236345+00
b2222222-0000-0000-0000-000000000003	Prepaid Travel Card	PrepaidAccess	{"maxLoadUsd": 10000, "reloadable": true}	United Arab Emirates	New	\N	\N	2026-09-22 14:00:37.236345+00
b2222222-0000-0000-0000-000000000004	Correspondent Settlement Account	CorrespondentBanking	{"nestedAccountsAllowed": false}	Kenya	New	\N	\N	2026-09-22 14:00:37.236345+00
b2222222-0000-0000-0000-000000000005	Private Banking Trade Finance Line	TradeFinance	{"facilityLimitUsd": 2000000}	Switzerland	FeatureAdd	\N	\N	2026-09-22 14:00:37.236345+00
\.


--
-- Data for Name: crm_customer; Type: TABLE DATA; Schema: mock_systems; Owner: -
--

COPY mock_systems.crm_customer (id, customer_name, customer_type, customer_geography, segment_classification, kyc_status, risk_flag, created_at) FROM stdin;
a1111111-0000-0000-0000-000000000001	Meridian Textiles Ltd	Corporate	Bangladesh	Commercial	Verified	\N	2026-09-22 14:00:37.236345+00
a1111111-0000-0000-0000-000000000002	Riya Kapoor	Individual	United States	Retail	Verified	\N	2026-09-22 14:00:37.236345+00
a1111111-0000-0000-0000-000000000003	Al-Sharq Money Exchange	MSB	United Arab Emirates	Commercial	Flagged	\N	2026-09-22 14:00:37.236345+00
a1111111-0000-0000-0000-000000000004	Global Relief Foundation	NGO	Kenya	Commercial	Pending	\N	2026-09-22 14:00:37.236345+00
a1111111-0000-0000-0000-000000000005	Fenwick & Cole Boutique Advisors	SmallBusiness	United Kingdom	PrivateBanking	Verified	\N	2026-09-22 14:00:37.236345+00
a1111111-0000-0000-0000-000000000006	Novak Family Trust	Individual	Switzerland	PrivateBanking	Verified	\N	2026-09-22 14:00:37.236345+00
\.


--
-- Data for Name: vendor_registry; Type: TABLE DATA; Schema: mock_systems; Owner: -
--

COPY mock_systems.vendor_registry (id, vendor_name, vendor_risk_rating, vendor_jurisdiction, data_access_scope, certification_status, updated_risk_rating, created_at) FROM stdin;
c3333333-0000-0000-0000-000000000003	Northbridge Document Services	Low	Canada	Scanned onboarding documents only	Certified	\N	2026-09-22 14:00:37.236345+00
c3333333-0000-0000-0000-000000000004	Vantage AML Screening Ltd	Medium	United Kingdom	Sanctions/PEP screening queries	Pending	\N	2026-09-22 14:00:37.236345+00
c3333333-0000-0000-0000-000000000002	QuickPay Processing LLC	High	Cayman Islands	Full transaction data, card PANs	None	Approved with conditions: Jordan Blake: Vendor must obtain SOC 2 Type II certification within 90 days of go-live; quarterly compliance attestation required for the first year.	2026-09-22 14:00:37.236345+00
c3333333-0000-0000-0000-000000000001	Global KYC Solutions Inc	Medium	Singapore	Customer PII for identity verification	Certified	Low - approved without conditions	2026-09-22 14:00:37.236345+00
\.


--
-- Data for Name: app_user; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_user (id, auth0_subject, email, display_name, is_active, created_at) FROM stdin;
a6a709a7-65e7-4a90-9b58-cbbaec1d651a	seed|product-owner-1	po1@example.bank	Priya Owens	t	2026-09-22 13:52:15.218393+00
4fa322d3-2245-44ef-b664-1a804442db23	seed|analyst-1	analyst1@example.bank	Amara Chen	t	2026-09-22 13:52:15.218393+00
1329f6a2-3450-438e-8a5f-b7b9ae219b67	seed|analyst-2	analyst2@example.bank	Sam Okafor	t	2026-09-22 13:52:15.218393+00
083ecfe5-aa01-4703-9168-762f0065078f	seed|committee-1	committee1@example.bank	Jordan Blake	t	2026-09-22 13:52:15.218393+00
fa142c1c-58cc-4666-b135-7768a2ab33f0	seed|committee-2	committee2@example.bank	Riley Voss	t	2026-09-22 13:52:15.218393+00
374a3158-6dfa-41f2-9a4d-3d1091dffacf	seed|admin-1	admin1@example.bank	Taylor Finch	t	2026-09-22 13:52:15.218393+00
7d392926-913b-4f9b-9d4a-b8163af6147b	seed|full-access-1	qa-full-access@example.bank	QA Full Access	t	2026-10-07 14:33:43.506104+00
\.


--
-- Data for Name: app_user_role; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_user_role (user_id, role, granted_by_user_id, reason, created_at) FROM stdin;
083ecfe5-aa01-4703-9168-762f0065078f	CommitteeMember	\N	Migrated from single-role app_user.role column	2026-10-07 14:32:50.246647+00
4fa322d3-2245-44ef-b664-1a804442db23	Analyst	\N	Migrated from single-role app_user.role column	2026-10-07 14:32:50.246647+00
fa142c1c-58cc-4666-b135-7768a2ab33f0	CommitteeMember	\N	Migrated from single-role app_user.role column	2026-10-07 14:32:50.246647+00
a6a709a7-65e7-4a90-9b58-cbbaec1d651a	ProductOwner	\N	Migrated from single-role app_user.role column	2026-10-07 14:32:50.246647+00
374a3158-6dfa-41f2-9a4d-3d1091dffacf	Admin	\N	Migrated from single-role app_user.role column	2026-10-07 14:32:50.246647+00
1329f6a2-3450-438e-8a5f-b7b9ae219b67	Analyst	\N	Migrated from single-role app_user.role column	2026-10-07 14:32:50.246647+00
7d392926-913b-4f9b-9d4a-b8163af6147b	Admin	\N	Initial seed grant	2026-10-07 14:33:43.506104+00
7d392926-913b-4f9b-9d4a-b8163af6147b	CommitteeMember	\N	Initial seed grant	2026-10-07 14:33:43.506104+00
7d392926-913b-4f9b-9d4a-b8163af6147b	Analyst	\N	Initial seed grant	2026-10-07 14:33:43.506104+00
7d392926-913b-4f9b-9d4a-b8163af6147b	ProductOwner	\N	Initial seed grant	2026-10-07 14:33:43.506104+00
\.


--
-- Data for Name: assessment; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.assessment (id, change_request_id, status, finalized_by_user_id, finalized_at, created_at) FROM stdin;
ab53a956-17d9-44bf-a92c-f34295d517ff	8400daf2-14ec-489a-878f-2053e67a1d31	Draft	\N	\N	2026-09-22 15:28:31.951764+00
9cf350cf-b9d2-4b1e-8f49-4661be9594bb	87057aee-66d0-4eed-b503-ee593be28113	Finalized	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-22 15:42:31.944065+00	2026-09-22 15:34:20.551909+00
bcef5b36-6d28-4778-8653-4ea2b2798edf	bd7b9737-77c8-4564-8a78-2d64ba3060a3	Finalized	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-24 17:32:52.022436+00	2026-09-24 17:19:49.267777+00
709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	89313b30-9064-4caa-8838-29e42ddc72f2	Finalized	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 06:53:49.633755+00	2026-09-25 06:53:47.617782+00
12f0ad4a-87e9-494c-924e-20be52169763	83f2c245-439e-4b8a-8206-ee1bda436d80	Finalized	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 06:58:42.052363+00	2026-09-25 06:58:41.247839+00
b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	298d4e01-a257-407a-9f27-04b96c02ff54	Finalized	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 06:59:36.431115+00	2026-09-25 06:58:39.374216+00
35b32ea9-b582-47a4-ad59-ad953bc0f5af	d80b9214-6103-4950-bbbf-e2ed93d18531	Finalized	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 06:59:46.528673+00	2026-09-25 06:59:46.15236+00
d434153a-e47d-42e2-9009-b9390394d50b	aff5b2e9-5ae7-4adf-8bf8-23de8bdca397	Draft	\N	\N	2026-09-25 07:02:21.127777+00
9c444cfb-245b-4b29-9778-592b4a6ea4d2	9782168a-6d7f-479a-ae0a-ca201f728af2	Finalized	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 07:02:32.405157+00	2026-09-25 07:02:32.026949+00
1de4b6d9-bc92-441c-8299-fe6b4d9fcc2e	9c73424d-30b2-4a3e-8881-c25af94572ba	Draft	\N	\N	2026-09-25 07:11:34.399672+00
50f965f9-70e5-4c4d-bec5-36017302898e	18404cb0-2e0b-4ef4-9a7d-b06fffe699f5	Finalized	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 07:22:24.397786+00	2026-09-25 07:22:23.622264+00
eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	ef797803-aaf9-4a7a-b7af-a86f6f010f9a	Finalized	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 07:23:22.966726+00	2026-09-25 07:22:21.822843+00
25ab4813-e18f-49c9-a50e-8541b5d63a10	b1c408c0-01d2-4d51-b5e9-20cb5fdfba0a	Finalized	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 07:23:34.030714+00	2026-09-25 07:23:33.634638+00
416b67b7-55af-4246-b3e1-22ef35c2202a	de00fb95-f4e9-4c55-9d17-781709873552	Draft	\N	\N	2026-09-25 07:23:47.743389+00
7942e391-5a34-46ca-a3d7-6cbf46a5d164	eee96cea-4f87-4d0d-95bd-565397ba8cea	Finalized	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 07:23:59.557587+00	2026-09-25 07:23:59.184479+00
a46d7e97-e303-4945-bf55-5ff7405b2a25	507e6f32-ab80-40db-81bd-5f641ef033a4	Finalized	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 07:28:40.58401+00	2026-09-25 07:26:12.747478+00
8a1fcb59-764d-4ca8-b3c3-d5f9558d304a	95c5cf1d-f648-489c-8391-20721104947f	Draft	\N	\N	2026-09-25 07:30:47.668113+00
90b8631a-dba0-43a1-b722-92176fd4bd13	540ffca2-0e67-4ed9-9e72-39e1aa12152d	Finalized	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-28 08:00:36.902328+00	2026-09-28 08:00:36.167148+00
9534f3f0-685a-4450-bfc0-983f2d16f7d9	617f16d3-e50b-487c-a31d-cedbbc7b572a	Finalized	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-28 08:01:47.92983+00	2026-09-28 08:00:34.492625+00
c00848c0-50fa-4a02-bcf8-e7967c9a92c9	2afd7b9b-a899-466e-82e2-e58da781599a	Finalized	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-28 08:01:59.186728+00	2026-09-28 08:01:58.771028+00
fef65e9f-675f-4a97-bed4-ab32decd986a	a3e3e745-edef-45d1-a62f-c20dbb048de0	Draft	\N	\N	2026-09-28 08:02:14.660436+00
8a3f06ba-72ed-4b2c-bb1c-b6c92f890f3f	e7983599-9aee-492c-8444-8764ae4892d9	Finalized	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-28 08:02:28.502291+00	2026-09-28 08:02:28.105223+00
fe6f95b7-3a35-4799-9eb2-e3239a6a3674	a6bbfac6-7b11-45b5-8c48-74c1efc1a343	Finalized	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-28 08:07:26.002355+00	2026-09-28 08:05:11.302117+00
3e2b8e40-cfa0-46c2-b6d2-48ae9e85c649	455cb36d-c05b-46f3-bba4-2769c127a7d3	Finalized	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-28 08:32:05.578264+00	2026-09-28 08:31:13.958582+00
eb5c9dbb-e31b-4d8b-8820-d13aa90fabc1	7a379245-0ee3-414a-884d-de47fc4ae358	Finalized	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-28 08:39:17.89468+00	2026-09-28 08:39:16.534655+00
1887751d-52fb-4229-b25e-a1a2204df89c	f278bcec-0b6e-4cad-a299-3cf307eb2a01	Draft	\N	\N	2026-09-29 08:13:52.443819+00
0db7ab6a-e107-4f80-93c6-05c73df4c70b	823b48e6-5235-4fdf-9aa9-17ceb9417cd5	Draft	\N	\N	2026-09-29 11:04:38.517019+00
3a72b012-35ca-4baf-be5d-4dafcf02cd11	724a96ec-6d75-4ebd-9ed5-d15d7abcccca	Draft	\N	\N	2026-09-30 10:40:38.288417+00
6e3cb87c-89cf-41ae-9629-15e5ae88b2ca	846abe95-3e9a-438f-9b30-0c7097371a27	Finalized	1329f6a2-3450-438e-8a5f-b7b9ae219b67	2026-09-30 12:57:37.763475+00	2026-09-30 11:23:56.113893+00
ac73a01a-7fcb-4091-b153-c974339a2ea4	7a6b4b58-4a23-4844-8c3b-fd20377a720f	Draft	\N	\N	2026-09-30 14:47:50.459809+00
386b9113-a53e-4b90-a396-35e574b2bfa3	d92baa78-c3dc-4ea5-ac3f-89b79959397d	Draft	\N	\N	2026-10-05 09:15:06.661625+00
b2a913c6-c962-4dfd-9961-810e58affc32	ac11f587-ee4f-40e6-a72f-e7e8f6be308a	Finalized	4fa322d3-2245-44ef-b664-1a804442db23	2026-10-05 09:27:25.125327+00	2026-09-29 10:07:38.434547+00
7efbc77f-e376-4244-b8b2-d4ea9dd26622	bf57f2fb-8d22-4567-a0d3-6eed60680461	Draft	\N	\N	2026-10-05 09:37:24.466161+00
8d5b74bf-e52d-4e0d-8606-7e0cf1100d7c	a7ae047c-a52c-40dd-a9d6-7840e8e7a87a	Draft	\N	\N	2026-10-05 09:37:25.945641+00
e58102ff-6105-4be7-8f8a-befe3c0167ac	1676366d-3ee4-4d55-993d-afcd3dc38b9a	Draft	\N	\N	2026-10-05 09:39:03.583992+00
fff06936-6523-4cbd-92a6-b6c07720b7e8	3f0eaf26-cf7d-4bb3-921c-162f6ae43a3d	Draft	\N	\N	2026-10-05 09:41:47.910354+00
c978c64d-b1b5-4754-b40b-d99151b874ca	4fe145bd-924b-4d09-83c4-3d9b3981a88d	Draft	\N	\N	2026-10-05 09:48:44.082347+00
3d7cce2d-cd7f-4fc2-9eef-fc7866889235	1db33cf3-d01d-4b60-8466-20fce8524875	Draft	\N	\N	2026-10-05 09:58:31.596238+00
e7d3ed87-4b56-4392-a0c0-464e852c3c67	90acf576-4272-4b63-bf8c-b55461910c28	Draft	\N	\N	2026-10-07 14:36:59.327602+00
\.


--
-- Data for Name: assessment_category_mapping; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.assessment_category_mapping (id, assessment_id, risk_category_id, source, ai_citation, is_active, created_by_user_id, created_at) FROM stdin;
1cb87792-6f07-4bf0-8973-8f4722aa6add	9cf350cf-b9d2-4b1e-8f49-4661be9594bb	22222222-2222-2222-2222-222222222222	AiProposed	FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Customers	t	\N	2026-09-22 15:34:33.256392+00
08034967-bfce-49a7-997b-37af38785140	9cf350cf-b9d2-4b1e-8f49-4661be9594bb	22222222-2222-2222-2222-222222222224	AnalystAdded	\N	t	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-22 15:34:49.136386+00
b9ddd204-0a1b-4789-90c4-83519bd4d76c	bcef5b36-6d28-4778-8653-4ea2b2798edf	22222222-2222-2222-2222-222222222221	AiProposed	FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Products and Services	t	\N	2026-09-24 17:20:00.84284+00
64284d0c-a39d-4d31-95c1-79aec6b6ed1a	bcef5b36-6d28-4778-8653-4ea2b2798edf	22222222-2222-2222-2222-222222222224	AnalystAdded	\N	t	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 06:27:57.425607+00
a82905b6-ddfe-47ca-a728-9ee721cb1c14	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	22222222-2222-2222-2222-222222222222	AiProposed	FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Customers	t	\N	2026-09-25 06:53:54.517089+00
8b27f16c-085d-48b5-8cde-3c433ec983a3	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	22222222-2222-2222-2222-222222222223	AnalystAdded	\N	t	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 06:53:56.719885+00
1609446d-6088-4bc5-8cb6-a93ee2724ff8	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	22222222-2222-2222-2222-222222222224	AnalystAdded	\N	t	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 06:53:57.026033+00
da627fc8-b5f9-4374-bbe6-a87d1236cb44	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	22222222-2222-2222-2222-222222222221	AnalystAdded	\N	t	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 06:54:44.663647+00
d6a5a12f-d5ee-485e-9778-e6d4fc2f95ff	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	22222222-2222-2222-2222-222222222222	AiProposed	FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Customers	t	\N	2026-09-25 06:58:45.996506+00
a53f2ebc-05f5-4585-91ca-d25a4bddd0d0	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	22222222-2222-2222-2222-222222222223	AnalystAdded	\N	t	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 06:58:49.247879+00
36f8a528-bb96-4c8d-8e1f-cbe00dad8f65	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	22222222-2222-2222-2222-222222222224	AnalystAdded	\N	t	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 06:58:49.577231+00
53c6177f-948a-4c2a-a729-7abcdd816a3d	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	22222222-2222-2222-2222-222222222221	AnalystAdded	\N	t	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 06:59:39.183212+00
8de2d092-c99a-416b-9e50-d58129c38433	1de4b6d9-bc92-441c-8299-fe6b4d9fcc2e	22222222-2222-2222-2222-222222222222	AiProposed	FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Customers	t	\N	2026-09-25 07:11:50.014946+00
b7227f5e-6ea8-45f6-82ad-4e931b1567ac	1de4b6d9-bc92-441c-8299-fe6b4d9fcc2e	22222222-2222-2222-2222-222222222223	AnalystAdded	\N	t	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 07:11:57.954562+00
ac1bb45b-1976-4279-bb68-2463f3319460	1de4b6d9-bc92-441c-8299-fe6b4d9fcc2e	22222222-2222-2222-2222-222222222224	AnalystAdded	\N	t	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 07:11:58.464248+00
3104cd90-9650-45c0-ba54-a0c69f1512e4	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	22222222-2222-2222-2222-222222222222	AiProposed	FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Customers	t	\N	2026-09-25 07:22:28.181692+00
50856e97-3118-4319-8d00-bea81ee5e589	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	22222222-2222-2222-2222-222222222223	AnalystAdded	\N	t	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 07:22:30.50241+00
aafa75fc-965b-4f03-bc3e-d02c0f89aa81	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	22222222-2222-2222-2222-222222222224	AnalystAdded	\N	t	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 07:22:30.814147+00
644784b9-f43a-4f67-9197-3ee3df47709c	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	22222222-2222-2222-2222-222222222221	AnalystAdded	\N	t	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 07:23:25.85331+00
62539f4f-631e-4767-b794-09075b9af826	a46d7e97-e303-4945-bf55-5ff7405b2a25	22222222-2222-2222-2222-222222222222	AiProposed	FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Customers	t	\N	2026-09-25 07:26:28.419591+00
bdb8ac55-950b-42cf-9f9e-bbada977c064	a46d7e97-e303-4945-bf55-5ff7405b2a25	22222222-2222-2222-2222-222222222224	AiProposed	FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Products and Services (Delivery Channels)	t	\N	2026-09-25 07:26:28.460184+00
9ea143f1-54a5-43ed-b020-a6fe379e1b96	a46d7e97-e303-4945-bf55-5ff7405b2a25	22222222-2222-2222-2222-222222222223	AnalystAdded	\N	t	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 07:26:36.274804+00
0059904e-b067-4a97-b45b-064e2919712e	9534f3f0-685a-4450-bfc0-983f2d16f7d9	22222222-2222-2222-2222-222222222222	AiProposed	FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Customers	t	\N	2026-09-28 08:00:42.461151+00
79abf61f-67ac-4f8f-97e2-2da55aa55af7	9534f3f0-685a-4450-bfc0-983f2d16f7d9	22222222-2222-2222-2222-222222222223	AnalystAdded	\N	t	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-28 08:00:46.500875+00
31c31263-0172-4071-961c-486097d2d728	9534f3f0-685a-4450-bfc0-983f2d16f7d9	22222222-2222-2222-2222-222222222224	AnalystAdded	\N	t	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-28 08:00:46.801393+00
b0a2383d-86c3-42e5-bdc6-dca43318c191	9534f3f0-685a-4450-bfc0-983f2d16f7d9	22222222-2222-2222-2222-222222222221	AnalystAdded	\N	t	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-28 08:01:50.767304+00
d4ecc71e-6db1-4389-b0ac-fa4c09f2b2ca	fe6f95b7-3a35-4799-9eb2-e3239a6a3674	22222222-2222-2222-2222-222222222222	AiProposed	FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Customers	t	\N	2026-09-28 08:05:27.540723+00
c31d1ada-e59a-4691-be12-9b081a7c1772	fe6f95b7-3a35-4799-9eb2-e3239a6a3674	22222222-2222-2222-2222-222222222224	AiProposed	FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Products and Services (Delivery Channels)	t	\N	2026-09-28 08:05:27.580263+00
a2e1b5c8-9a54-42a3-8019-9e2739446cc3	fe6f95b7-3a35-4799-9eb2-e3239a6a3674	22222222-2222-2222-2222-222222222223	AnalystAdded	\N	t	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-28 08:05:34.266294+00
3ca5da75-f679-4b1e-ade9-c535cf98336b	b2a913c6-c962-4dfd-9961-810e58affc32	22222222-2222-2222-2222-222222222221	AiProposed	FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Products and Services	t	\N	2026-09-29 10:07:45.86419+00
8f53b248-81f2-4509-bc1f-753b4a2ddbae	3a72b012-35ca-4baf-be5d-4dafcf02cd11	22222222-2222-2222-2222-222222222221	AiProposed	FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Products and Services	t	\N	2026-09-30 10:40:45.405304+00
a18d102f-5680-4590-ac0c-8caf602fbf62	6e3cb87c-89cf-41ae-9629-15e5ae88b2ca	22222222-2222-2222-2222-222222222221	AiProposed	FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Products and Services	t	\N	2026-09-30 11:37:35.869386+00
fdd2eeb8-a780-449d-b674-2c678a93af0a	6e3cb87c-89cf-41ae-9629-15e5ae88b2ca	22222222-2222-2222-2222-222222222223	AnalystAdded	\N	t	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-30 11:39:49.804002+00
5ea176d9-b9d2-4975-a663-adf059d1a74a	6e3cb87c-89cf-41ae-9629-15e5ae88b2ca	22222222-2222-2222-2222-222222222222	AnalystAdded	\N	t	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-30 11:39:19.23359+00
32393fb5-efef-42eb-9704-3c9c345dfec6	6e3cb87c-89cf-41ae-9629-15e5ae88b2ca	22222222-2222-2222-2222-222222222224	AnalystAdded	\N	f	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-30 11:42:01.378758+00
e9eb54ce-2095-4687-a137-80d84a600d3f	0db7ab6a-e107-4f80-93c6-05c73df4c70b	22222222-2222-2222-2222-222222222221	AiProposed	FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Products and Services	t	\N	2026-09-30 14:32:49.729582+00
92b68792-1baa-4557-8baf-802a03fe8e51	386b9113-a53e-4b90-a396-35e574b2bfa3	22222222-2222-2222-2222-222222222222	AnalystAdded	\N	t	4fa322d3-2245-44ef-b664-1a804442db23	2026-10-05 09:16:25.868279+00
d1b4fea3-f3b4-447e-9335-740a61e29112	386b9113-a53e-4b90-a396-35e574b2bfa3	22222222-2222-2222-2222-222222222223	AnalystAdded	\N	t	4fa322d3-2245-44ef-b664-1a804442db23	2026-10-05 09:17:47.7952+00
5c2a6d47-9b0a-402e-afe0-a9945b1f8620	386b9113-a53e-4b90-a396-35e574b2bfa3	22222222-2222-2222-2222-222222222221	AnalystAdded	\N	f	4fa322d3-2245-44ef-b664-1a804442db23	2026-10-05 09:17:57.895533+00
e415d52c-2791-499f-b7fe-d52f9933fb8b	8d5b74bf-e52d-4e0d-8606-7e0cf1100d7c	22222222-2222-2222-2222-222222222222	AnalystAdded	\N	f	4fa322d3-2245-44ef-b664-1a804442db23	2026-10-05 09:37:26.387653+00
e9615daa-90fc-4bd6-bc32-830bda18af10	e58102ff-6105-4be7-8f8a-befe3c0167ac	22222222-2222-2222-2222-222222222222	AnalystAdded	\N	t	4fa322d3-2245-44ef-b664-1a804442db23	2026-10-05 09:39:04.058453+00
ecfe53b8-fb9d-4433-afbb-b134775afd63	386b9113-a53e-4b90-a396-35e574b2bfa3	22222222-2222-2222-2222-222222222224	AnalystAdded	\N	t	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-10-05 09:17:39.703211+00
\.


--
-- Data for Name: assessment_narrative_section; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.assessment_narrative_section (id, assessment_id, risk_category_id, narrative_text, status, unsupported_claim_flags, updated_by_user_id, updated_at) FROM stdin;
c957bc7f-31f3-4c6a-8917-ab3233c86fd2	9cf350cf-b9d2-4b1e-8f49-4661be9594bb	22222222-2222-2222-2222-222222222222	The proposed onboarding of QuickPay Processing LLC as a vendor to process full transaction data and card primary account numbers (PANs) for our new prepaid settlement flow involves considerations relevant to elevated money laundering risk. According to the FFIEC BSA/AML Manual, certain customers and entities, including those operating in higher-risk jurisdictions and industries, require enhanced scrutiny under a risk-based customer due diligence framework (Risks Associated with Money Laundering and Terrorist Financing - Customers). QuickPay Processing LLC is based in the Cayman Islands, which necessitates a careful assessment of their money laundering and terrorist financing risk profile due to the jurisdiction's heightened risk factors. Additionally, the vendor will have access to sensitive cardholder personally identifiable information (PII), which further underscores the importance of diligent controls and oversight. Given the lack of a compliance certification on file for QuickPay Processing LLC, the institution must ensure adequate due diligence and risk mitigation procedures are established so that the vendor's role aligns with the bank's broader financial crimes risk management policies.	AnalystReviewed	["The Cayman Islands is a higher-risk jurisdiction specifically requiring enhanced due diligence for this vendor type", "QuickPay Processing LLC is a money services business or falls under other specific elevated risk categories", "Details about the vendor's anti-money laundering controls or compliance certifications aside from the absence of a certification on file"]	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-22 15:41:04.659102+00
49a04fe9-4b96-4537-b649-f2804151f911	9cf350cf-b9d2-4b1e-8f49-4661be9594bb	22222222-2222-2222-2222-222222222224	The proposed business change involves onboarding QuickPay Processing LLC, a vendor based in the Cayman Islands, to process full transaction data and card PANs for the new prepaid settlement flow. This introduces delivery channel risks associated with utilizing a third-party processor in a foreign jurisdiction without a current compliance certification on file. Given the significant scope of data access, including cardholder personally identifiable information (PII), there is an elevated risk of money laundering and terrorist financing that must be mitigated through enhanced due diligence and ongoing oversight.\n\nAccording to the FFIEC BSA/AML Manual section on Risks Associated with Money Laundering and Terrorist Financing: Products and Services (Delivery Channels), the use of remote or less transparent delivery channels such as third-party vendors in offshore jurisdictions requires comprehensive risk assessment and controls to manage potential vulnerabilities. The lack of compliance certification for QuickPay Processing LLC further intensifies these risks, underscoring the need for thorough vendor risk management practices before full integration into the bank's prepaid settlement processes.	AnalystReviewed	[]	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-22 15:41:05.114551+00
3b8af7a7-200a-4623-907c-68c4610b07b4	bcef5b36-6d28-4778-8653-4ea2b2798edf	22222222-2222-2222-2222-222222222221	The proposed launch of the AzureFoundry E2E Test for a prepaid card product introduces inherent risks consistent with those identified in the FFIEC BSA/AML Manual concerning products and services vulnerable to money laundering and terrorist financing. Specifically, prepaid access products are noted for their susceptibility due to rapid movement of funds and the potential for limited face-to-face interactions, which may complicate customer verification and transaction monitoring processes. Prior to the launch of such products, it is essential that the bank has adequately identified, measured, and implemented effective controls to mitigate these risks, as outlined in the supervisory guidance (Risks Associated with Money Laundering and Terrorist Financing - Products and Services). Given the nature of the test involving an AI provider and category mapping, the bank should ensure that AML controls are integrated into the product's design and deployment to prevent exploitation by illicit actors.	AnalystReviewed	["The specific AML controls the bank plans to implement for the AzureFoundry prepaid card product.", "Any potential changes in customer due diligence procedures due to the AI provider integration.", "The exact nature or structure of the rapid fund movements anticipated with the prepaid card product during testing."]	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-24 17:32:31.872682+00
4093f912-043c-4563-84ea-2579492247bd	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	22222222-2222-2222-2222-222222222223	The proposed business change involves onboarding a vendor, QA corrected value, a Malta-based card settlement processor. This vendor will have access to sensitive cardholder personally identifiable information (PII) and settlement files. Given that Malta is the vendor's jurisdiction, the bank must evaluate the geographic risks associated with money laundering and terrorist financing in this location as outlined in the FFIEC BSA/AML Manual under Geographic Locations risks.\\n\\nAccess to cardholder PII and settlement data via an API in a non-face-to-face delivery channel inherently raises concerns about transaction monitoring and data security due to the increased risk profile of remote interactions. The impact extends across customer types, including retail cardholders and money services business (MSB) merchants, both of whom could be vulnerable to illicit activity facilitated through this vendor relationship.\\n\\nThe bank’s risk management should ensure enhanced due diligence and ongoing monitoring to address the potential exposure introduced through this geographic location, focusing on compliance with the guidance provided in the FFIEC BSA/AML Manual concerning geographic risks related to money laundering and terrorist financing.	AnalystReviewed	[]	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 06:54:29.94835+00
e923f480-f683-4919-94ff-562dd2b26cd6	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	22222222-2222-2222-2222-222222222224	The proposed business change involves onboarding a Malta-based vendor named QA as a card settlement processor, granting the vendor access to cardholder personally identifiable information (PII) and settlement files. This onboarding introduces a non-face-to-face delivery channel through an API interface, which inherently increases the complexity and risks associated with money laundering and terrorist financing activities, as noted in the FFIEC BSA/AML Manual under "Risks Associated with Money Laundering and Terrorist Financing: Products and Services (Delivery Channels)". The lack of direct, in-person interaction in this API-based delivery channel underscores the importance of robust risk controls and monitoring mechanisms to mitigate the elevated risks.	AnalystReviewed	[]	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 06:54:30.229255+00
30aed139-f516-44c7-b390-dc43d50816dc	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	22222222-2222-2222-2222-222222222222	post-finalize tamper	AnalystEdited	[]	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 06:54:44.059194+00
f1fa018c-1349-40b0-8ff4-ee2d04358709	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	22222222-2222-2222-2222-222222222223	The proposed onboarding of the Malta-based vendor, QA corrected value, introduces a new geographic risk factor associated with access to cardholder PII and settlement files. As the vendor operates in Malta, the bank must consider the inherent risks tied to geographic jurisdictions, in line with the FFIEC BSA/AML Manual guidance on Risks Associated with Money Laundering and Terrorist Financing: Geographic Locations. The use of a non-face-to-face delivery channel via API further elevates these risks by reducing the bank's ability to directly verify customer identity and intent, as specified in the policy section on Delivery Channels. This lack of face-to-face interaction requires enhanced due diligence and risk assessment measures to mitigate potential exploitation by illicit actors.\n\nMoreover, the affected customer types—including retail cardholders and MSB merchants—reflect a diverse set of clients, whose varying risk profiles must be factored comprehensively. Because the third-party vendor gains access to sensitive data through API channels, the bank should carefully evaluate its onboarding protocols, ensuring the vendor meets stringent data protection and AML compliance standards specific to the Malta jurisdiction. This is essential to manage risks tied to cross-border data flows and potential regulatory divergences in geographic risk contexts.	AnalystReviewed	[]	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 06:59:23.789242+00
f2f9f73f-1bc1-452f-9c7f-39bdf40e0882	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	22222222-2222-2222-2222-222222222224	The introduction of the Malta-based vendor 'QA corrected value' as a settlement processor providing access to cardholder PII and settlement files represents a notable change in the bank's delivery channels. Given the non-face-to-face API integration, this channel inherently increases exposure to risks associated with electronic access to sensitive customer information, particularly for retail cardholders and MSB merchants, as outlined in the FFIEC BSA/AML Manual regarding Delivery Channels risk (Risks Associated with Money Laundering and Terrorist Financing: Products and Services (Delivery Channels)). The reliance on an overseas vendor in Malta, a foreign jurisdiction, necessitates enhanced due diligence to ensure that the vendor's AML controls are robust and capable of mitigating risks tied to the vendor's own customer base (Correspondent Banking section).	AnalystReviewed	[]	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 06:59:24.062928+00
f43a13f5-a778-4467-bc61-381babc6c557	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	22222222-2222-2222-2222-222222222222	post-finalize tamper	AnalystEdited	[]	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 06:59:38.616471+00
68e3a33c-142e-4f32-bd3f-2d5b3376f96a	1de4b6d9-bc92-441c-8299-fe6b4d9fcc2e	22222222-2222-2222-2222-222222222222	QA analyst narrative: onboarding a Malta-domiciled settlement processor with API access to cardholder PII. EDD and annual audit rights required.	AnalystEdited	["The vendor's ownership structure is complex or opaque.", "The vendor presents a heightened risk of facilitating money laundering or terrorist financing.", "The bank has completed the beneficial ownership verification for QuickPay Processing Ltd."]	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 07:13:04.361434+00
697bb87d-c1ec-442a-88d0-d22ca6ff82b3	1de4b6d9-bc92-441c-8299-fe6b4d9fcc2e	22222222-2222-2222-2222-222222222223	The proposed vendor onboarding involves QuickPay Processing Ltd, a card settlement processor based in Malta. According to the FFIEC BSA/AML Manual section on Risks Associated with Money Laundering and Terrorist Financing: Geographic Locations, jurisdictions vary in their risk profiles based on factors such as the effectiveness of anti-money laundering controls and the presence of financial crimes. Malta, as the country of the vendor, represents a geographic consideration in assessing the financial crime risks associated with transmitting cardholder PII and settlement data.\n\nGiven the transaction flow involving sensitive personal information and financial data, the bank must evaluate Malta's risk characteristics as defined in the FFIEC guidance. This includes understanding any heightened risks of money laundering or terrorist financing linked to vendors situated in that jurisdiction. Although no specific mitigation measures or additional information are included in the provided facts, adherence to this policy section necessitates that the geographic risk be addressed appropriately during due diligence and ongoing monitoring of the vendor relationship.	AnalystReviewed	["Malta's specific AML or financial crime risk rating according to the FFIEC manual is high or low", "The vendor QuickPay Processing Ltd has prior history of compliance or non-compliance issues", "Specific mitigation steps or controls to address geographic risk have been established for this vendor"]	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 07:13:05.354451+00
07c0ea68-5e6e-4418-af8d-1115d57822d0	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	22222222-2222-2222-2222-222222222224	The proposed vendor onboarding involves a Malta-based card settlement processor, QA corrected value, which will access cardholder personally identifiable information (PII) and settlement files through an API delivery channel. This onboarding represents a non-face-to-face delivery channel, which inherently carries risk considerations for money laundering and terrorist financing due to the lack of in-person verification. As noted in the FFIEC BSA/AML Manual, delivery channels such as APIs facilitating remote transactions necessitate heightened vigilance in monitoring for suspicious activity (Delivery Channels section).\n\nGiven that Malta is a foreign jurisdiction, this relationship may be analogously considered in light of correspondent banking risk principles related to foreign financial institutions. Specifically, the policy excerpt emphasizes enhanced due diligence for foreign correspondent relationships, especially in higher-risk jurisdictions (Risks Associated with Money Laundering and Terrorist Financing - Correspondent Banking). While Malta is not explicitly classified here, the principle of assessing the adequacy of the vendor's AML controls and monitoring the transaction patterns remains critical.\n\nThe affected customer types include retail cardholders and MSB merchants, both of which could present diverse risk profiles. Accordingly, robust AML controls and continuous monitoring of transaction activity flowing through this API-based settlement vendor should be maintained to effectively mitigate delivery channel risks and align with the supervisory expectations delineated in the FFIEC guidance.	AnalystReviewed	["Malta is considered a higher-risk jurisdiction for AML purposes", "The vendor uses nested account arrangements"]	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 07:23:09.601868+00
d41ca34c-ab7b-4f0b-81f9-fc03ca6af113	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	22222222-2222-2222-2222-222222222223	The proposed change involves onboarding a Malta-based card settlement processor, QA corrected value, which will have access to cardholder PII and settlement files. This vendor will serve retail cardholders and MSB merchants through an API delivery channel, which is a non-face-to-face method. According to the FFIEC BSA/AML Manual on Risks Associated with Money Laundering and Terrorist Financing, non-face-to-face delivery channels, including reliance on third-party agents or correspondent relationships to deliver products, reduce a bank's ability to verify customer identity and intent directly, thereby increasing risk (Delivery Channels). Given that Malta is the vendor jurisdiction, it is critical to consider the geographic risk factors associated with operating in or contracting with vendors in that location, as outlined in the supervisory citation for Geographic Locations.	AnalystReviewed	[]	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 07:23:09.320051+00
a4483065-c1c3-4d27-8aa8-421a0a6dff45	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	22222222-2222-2222-2222-222222222222	post-finalize tamper	AnalystEdited	[]	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 07:23:25.253252+00
4d76c74f-0c7c-425c-8ee9-02323e60af93	a46d7e97-e303-4945-bf55-5ff7405b2a25	22222222-2222-2222-2222-222222222222	QA analyst narrative: onboarding a Malta-domiciled settlement processor with API access to cardholder PII. EDD and annual audit rights required.	AnalystEdited	["Malta is considered a higher-risk jurisdiction necessitating enhanced due diligence", "QuickPay Processing Ltd's AML controls have been evaluated and deemed sufficient"]	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 07:28:06.472729+00
59e9ae44-77fb-4de3-9817-f8d0149bdaec	a46d7e97-e303-4945-bf55-5ff7405b2a25	22222222-2222-2222-2222-222222222223	The proposed onboarding of QuickPay Processing Ltd, a vendor based in Malta, as a card settlement processor introduces geographic risk considerations as delineated in the FFIEC BSA/AML Manual. Geographic risk assessment focuses on exposure to jurisdictions identified by FATF for strategic AML/CFT deficiencies, jurisdictions under OFAC sanctions, and domestic High Intensity Financial Crime Areas (HIFCAs). While Malta is the vendor’s jurisdiction, it is essential to evaluate its standing relative to these critical risk indicators to determine the appropriate level of scrutiny. The vendor will handle sensitive cardholder personally identifiable information (PII) and settlement files via API, which heightens the importance of assessing the AML/CFT risks associated with their geographic location. Given that the policy mandates additional scrutiny for products, customers, and transactions connected to higher-risk jurisdictions, this vendor relationship warrants a thorough due diligence process to identify and mitigate such risks effectively (Risks Associated with Money Laundering and Terrorist Financing - Geographic Locations).	AnalystReviewed	[]	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 07:28:08.582623+00
90e2f3ba-fa19-4463-ab12-21ef4c7cf940	a46d7e97-e303-4945-bf55-5ff7405b2a25	22222222-2222-2222-2222-222222222224	The proposed business change involves onboarding QuickPay Processing Ltd., a Malta-based vendor, as a card settlement processor. The vendor will receive cardholder personally identifiable information (PII) and settlement files via an API. According to the FFIEC BSA/AML Manual section on Risks Associated with Money Laundering and Terrorist Financing regarding Delivery Channels, reliance on third-party agents and correspondent relationships to deliver products inherently increases risk due to the reduced ability of the bank to directly verify customer identity and intent. This reduction in direct verification capability necessitates a thorough risk assessment specific to the implications of using QuickPay Processing Ltd. as a settlement vendor.\n\nGiven that the vendor operates in a non-face-to-face, third-party capacity and will have access to sensitive cardholder data, it is critical that the bank's overall risk assessment explicitly addresses the risks introduced by the delivery channel change. This includes heightened consideration of identity validation challenges and potential vulnerabilities introduced by cross-jurisdictional operations with Malta. These risk factors must be carefully managed and mitigated in line with the guidance outlined in the FFIEC manual to ensure compliance and minimize exposure to financial crimes associated with delivery channels.	AnalystReviewed	[]	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 07:28:07.53501+00
0338c9b2-a2a5-4004-a183-f3d02286bb56	9534f3f0-685a-4450-bfc0-983f2d16f7d9	22222222-2222-2222-2222-222222222223	The proposed business change to onboard QA corrected value, a Malta-based card settlement vendor, introduces specific geographic risk considerations as outlined in the FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing. Malta, as the vendor's jurisdiction, presents inherent country-specific risks that must be evaluated due to potential vulnerabilities related to money laundering and terrorist financing in certain geographic locations. The access granted to the vendor includes cardholder personally identifiable information (PII) and settlement files, heightening the sensitivity of data involved.\n\nGiven that the delivery channel for this vendor's services is via an API, which is a non-face-to-face transaction channel, the concerns noted in the policy about reduced ability to verify customer identity and intent directly are applicable here. Reliance on such third-party arrangements through non-face-to-face channels amplifies the risk profile and should be thoroughly factored into the overall risk assessment of this change (Risks Associated with Money Laundering and Terrorist Financing - Delivery Channels). The impacted customer types encompass retail cardholders and money services business (MSB) merchants, emphasizing the need for diligent risk controls to mitigate exposure related to these groups.\n\nIn summary, the onboarding of this Malta-based vendor with API-based non-face-to-face access to sensitive cardholder and transaction data necessitates a comprehensive evaluation of geographic risks as well as the delivery channel risks described in the cited FFIEC manual excerpt. These factors must be integrated into the FCRM assessment to ensure appropriate monitoring and mitigation strategies are established.	AnalystReviewed	[]	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-28 08:01:32.557284+00
fe5cfe98-0efc-4524-a1db-1aabb69d89b4	9534f3f0-685a-4450-bfc0-983f2d16f7d9	22222222-2222-2222-2222-222222222222	post-finalize tamper	AnalystEdited	[]	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-28 08:01:50.20594+00
59d6e75a-6bb2-4339-b408-3c2ab91119cf	9534f3f0-685a-4450-bfc0-983f2d16f7d9	22222222-2222-2222-2222-222222222224	The proposed business change involves onboarding QA corrected value, a Malta-based card settlement processor, which will have access to cardholder personally identifiable information (PII) and settlement files through an API-based delivery channel. This constitutes a non-face-to-face electronic channel, which inherently carries heightened risks for money laundering and terrorist financing due to potential limitations in customer interaction and identification verification processes. Given the vendor's jurisdiction in Malta, the bank must consider country-specific risks as part of an enhanced due diligence process, consistent with expectations for correspondent relationships involving higher-risk jurisdictions, as outlined in the FFIEC BSA/AML Manual (Risks Associated with Money Laundering and Terrorist Financing - Correspondent Banking). Although the vendor is not a correspondent bank, parallel scrutiny is warranted because of the sensitive data access and the involvement in settlement processing that interfaces with the bank's retail cardholders and money services business (MSB) merchant customers. The arrangement should therefore incorporate appropriate AML controls tailored to these risks, including continuous monitoring of the vendor's compliance posture and transaction activities facilitated through the API delivery channel, to mitigate potential vulnerabilities related to money laundering or terrorist financing exploitation.	AnalystReviewed	["Malta is considered a higher-risk jurisdiction for AML by the bank or relevant regulator.", "The vendor's AML controls have been evaluated and found satisfactory or deficient.", "Specific enhanced due diligence procedures will be implemented in this vendor onboarding."]	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-28 08:01:32.846283+00
20191a3c-5862-48eb-af12-ced7e96486cb	fe6f95b7-3a35-4799-9eb2-e3239a6a3674	22222222-2222-2222-2222-222222222222	QA analyst narrative: onboarding a Malta-domiciled settlement processor with API access to cardholder PII. EDD and annual audit rights required.	AnalystEdited	["QuickPay Processing Ltd operates in a higher-risk sector", "QuickPay Processing Ltd is a non-resident alien entity", "Enhanced due diligence has been performed on QuickPay Processing Ltd"]	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-28 08:06:52.983354+00
6549925c-e621-4abb-b0bc-6b8b004c68e8	fe6f95b7-3a35-4799-9eb2-e3239a6a3674	22222222-2222-2222-2222-222222222224	The proposed onboarding of QuickPay Processing Ltd, a Malta-based vendor, as the card settlement processor involves the transmission of cardholder personally identifiable information (PII) and settlement files via an API. This change directly implicates the Delivery Channels risk category as outlined in the FFIEC BSA/AML Manual, specifically regarding risks associated with money laundering and terrorist financing through delivery channels. The policy underscores that non-face-to-face transaction channels and reliance on third-party agents can diminish a bank's direct ability to verify customer identity and intent, thereby increasing inherent risk (Risks Associated with Money Laundering and Terrorist Financing - Delivery Channels).\n\nGiven that QuickPay Processing Ltd will be integrated as a third-party service provider handling sensitive customer information remotely, the associated operational model aligns with the policy’s focus on increased risk resulting from third-party reliance. Therefore, this vendor onboarding must be carefully risk-assessed in accordance with the policy to ensure that appropriate controls are implemented to mitigate the potential reduction in direct identity verification capabilities and to manage the elevated exposure to financial crime threats through this delivery channel.	AnalystReviewed	[]	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-28 08:06:53.972435+00
2f34680d-b8de-4e93-a4fa-581cee259c5d	fe6f95b7-3a35-4799-9eb2-e3239a6a3674	22222222-2222-2222-2222-222222222223	The proposed business change involves onboarding QuickPay Processing Ltd, a vendor based in Malta, as a card settlement processor. This vendor will handle cardholder personally identifiable information (PII) and settlement files transmitted via an API. Given that Malta is the geographic location where the vendor operates, geographic risk factors must be considered in accordance with the FFIEC BSA/AML Manual guidance on Risks Associated with Money Laundering and Terrorist Financing. Specifically, risk assessment should consider whether Malta is identified by the Financial Action Task Force (FATF) as having strategic AML/CFT deficiencies, whether it is subject to any Office of Foreign Assets Control (OFAC) sanctions programs, or if it is designated as a domestic High Intensity Financial Crime Area (HIFCA) relevant to the bank's operations.\n\nAs there are no extracted facts indicating that Malta currently holds any such high-risk designations or sanctions, the baseline geographic risk associated with this vendor onboarding appears standard. Nonetheless, consistent with policy, the bank should apply additional scrutiny to products, customers, and transactions linked to Malta to mitigate potential exposure to geographic-based money laundering or terrorist financing risks, ensuring ongoing monitoring and compliance with all applicable regulatory expectations [Risks Associated with Money Laundering and Terrorist Financing - Geographic Locations].	AnalystReviewed	[]	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-28 08:06:54.452973+00
6222e9d0-a3fc-4b44-a2b6-cab617d1dd58	6e3cb87c-89cf-41ae-9629-15e5ae88b2ca	22222222-2222-2222-2222-222222222221	The proposed launch of the Prepaid Settlement Card introduces a reloadable prepaid debit card product serving retail consumers and cash-intensive small businesses, facilitating both domestic and cross-border point-of-sale and ATM transactions. As noted in the FFIEC BSA/AML Manual section on Products and Services, prepaid access products possess inherent vulnerabilities to money laundering due to characteristics such as rapid fund movements and limited face-to-face interactions. The product's fully online onboarding process without branch visits accentuates these inherent risks, necessitating robust mitigation strategies and risk measurement prior to rollout.\n\nThe product supports cross-border transactions in 12 countries, including two jurisdictions monitored by FATF, which may elevate risks given the increased complexity and varying anti-money laundering frameworks internationally. The inclusion of card-not-present online transactions further accentuates the necessity for enhanced controls to detect and prevent illicit activity. Additionally, third-party processing arrangements with QuickPay Processing Ltd and the use of SFTP-based daily settlement file exchanges introduce considerations related to data security and transaction monitoring within third-party ecosystems.\n\nGiven these factors aligned with the cited FFIEC guidance, it is imperative that the bank has identified, measured, and established mitigation controls for the specific risks associated with this prepaid access product offering before launch, particularly addressing vulnerabilities arising from non-face-to-face enrollment and cross-border functionality (Risks Associated with Money Laundering and Terrorist Financing - Products and Services). The exclusion of PEP and non-resident alien customers at launch may reduce some risk layers but does not eliminate inherent risks tied to this product type and delivery channel.	AnalystReviewed	[]	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-30 12:37:40.080982+00
c8f7f7b8-f3fe-4f01-ab5e-2267260930a4	b2a913c6-c962-4dfd-9961-810e58affc32	22222222-2222-2222-2222-222222222221	QA-FT 05Oct analyst edit: The product change introduces prepaid-style settlement exposure. Customer due diligence and transaction monitoring must cover reload limits and cross-border usage, per the FFIEC Products and Services section.	AnalystEdited	["The specific nature of the product or service change and its features", "Whether the change increases, decreases, or has no material effect on money laundering/terrorist financing risk", "Any existing controls, monitoring, or due diligence measures applicable to this product change", "Customer base or transaction volume characteristics associated with the change", "Geographic or channel risk factors relevant to the proposed change"]	4fa322d3-2245-44ef-b664-1a804442db23	2026-10-05 09:21:58.873896+00
5f7f6f13-3b22-44db-b4f5-43178e599f4d	6e3cb87c-89cf-41ae-9629-15e5ae88b2ca	22222222-2222-2222-2222-222222222223	The proposed launch of the Prepaid Settlement Card introduces a reloadable prepaid debit product tailored for retail and small-business customers, including those engaged in cash-intensive activities, with functionalities enabling both domestic and cross-border point-of-sale and ATM transactions. Given the inherent vulnerabilities of prepaid access products to money laundering due to rapid fund movements and limited face-to-face contact, as noted in the supervisory guidance on geographic locations risk (Risks Associated with Money Laundering and Terrorist Financing - Products and Services), it is critical to assess the geographic risks tied to cross-border transactions. This product supports cross-border transactions in UAE countries, including two FATF-monitored jurisdictions, which elevates the importance of robust geographic risk management and ongoing monitoring for potential illicit activity stemming from higher-risk locations. The onboarding process for the Prepaid Settlement Card is fully online without branch visits, which, combined with the product features, increases potential exposure to money laundering risks due to the non-face-to-face enrollment channel. However, the product does not target politically exposed persons (PEPs) or non-resident aliens (NRAs) at launch, narrowing certain customer risk dimensions. The involvement of the third-party processor QuickPay Processing Ltd and SFTP-based daily settlement file exchanges necessitates ensuring these partners have adequate controls to manage and monitor risks associated with geographic locations during transaction processing. Overall, the bank must ensure that its risk identification, measurement, and mitigation procedures fully incorporate the geographic risk considerations tied to cross-border prepaid card usage, particularly for the FATF-monitored jurisdictions covered. Appropriate transaction monitoring, customer due diligence, and oversight of third-party processing activities should be emphasized to address the geographic vulnerabilities associated with this prepaid access product as outlined in the FFIEC BSA/AML Manual risk framework.\n\n	AnalystEdited	["The third-party processor QuickPay Processing Ltd has adequate controls to manage geographic location risks.", "Ongoing monitoring programs are sufficient to mitigate geographic risks related to the FATF-monitored jurisdictions."]	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-30 12:36:53.697345+00
008d25c0-d694-4597-bf82-ae18cc0f29c5	6e3cb87c-89cf-41ae-9629-15e5ae88b2ca	22222222-2222-2222-2222-222222222222	The introduction of the Prepaid Settlement Card, a reloadable prepaid debit product targeted at retail consumers and cash-intensive small businesses, involves specific money laundering and terrorist financing risks inherent to prepaid access instruments. According to the FFIEC BSA/AML Manual, prepaid access products such as general-purpose reloadable cards are vulnerable due to their potential to facilitate structuring below reporting thresholds and movement of value with limited identity verification. Consequently, effective customer due diligence must align proportionally with the product's funding, reload, and redemption features (Prepaid Access Customers). The card enables multiple transaction types, including card-present point-of-sale, ATM withdrawals, and card-not-present online transactions, across domestic and cross-border environments. Cross-border capabilities include 12 countries, with two FATF-monitored jurisdictions, further increasing the need for tailored AML controls (Products and Services). \n\nThe onboarding process is fully digital and non-face-to-face, conducted via a mobile app without branch visits, which elevates risks related to identity verification and customer authentication. The bank’s exclusion of politically exposed persons (PEPs) and non-resident aliens (NRAs) as initial customers partially mitigates heightened risk exposure at launch. Data collected during onboarding includes sensitive personally identifiable information (PII) such as name, address, and partial Social Security number, alongside transaction history and device fingerprinting to enhance risk profiling. The use of a third-party processor, QuickPay Processing Ltd, and reliance on daily settlement data exchange via SFTP rather than real-time APIs, underscores the importance of ongoing monitoring and timely information sharing to detect suspicious activity. \n\nIn summary, the Prepaid Settlement Card’s inherent vulnerabilities from rapid fund movement and limited face-to-face interaction require the bank to implement robust customer due diligence and transaction monitoring controls proportionate to the product’s features and risks, consistent with supervisory guidance in the FFIEC BSA/AML Manual sections on Products and Services and Prepaid Access Customers.	AnalystReviewed	[]	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-30 12:37:35.176081+00
4cb41c7b-857f-4603-9f73-cd5f4b5432ef	0db7ab6a-e107-4f80-93c6-05c73df4c70b	22222222-2222-2222-2222-222222222221	This assessment addresses the proposed change titled "Deployed AI verify," which involves testing an Anthropic workspace-scoped call within the bank's deployed development environment. The change has been categorized under the Products & Services risk category, consistent with the FFIEC BSA/AML Manual's guidance on money laundering and terrorist financing risks associated with new products and services, which requires that financial institutions evaluate the inherent risk profile of new or modified products, services, and delivery channels before and during their introduction.\n\nAt this time, no specific policy excerpts beyond the applicable FFIEC citation and no extracted document facts have been supplied to support a detailed, fact-based risk characterization of this change. Consequently, this narrative cannot substantiate the nature of the underlying product functionality, its customer-facing impact, transaction volumes, data flows, or any compensating controls that may apply, as none of this information was provided in the source materials made available for this review.\n\nGiven the absence of supporting documentation, the Products & Services risk category determination for this change should be treated as preliminary. Before this assessment can be finalized, additional documentation describing the functional scope of the Anthropic workspace-scoped call, its intended production use (if any), and any associated customer or transactional touchpoints should be obtained and evaluated against the FFIEC BSA/AML Manual's Products and Services risk factors.	AiDrafted	["The AI verify product introduces new money laundering or terrorist financing risk", "The Anthropic workspace-scoped call has customer-facing or transactional impact", "The development environment deployment will transition to production use", "Specific control measures exist to mitigate risks associated with this change", "Transaction volumes, customer types, or geographic exposure associated with this change", "Data handled by the AI verify feature includes personally identifiable or financial information"]	\N	2026-09-30 17:27:06.52086+00
\.


--
-- Data for Name: assessment_policy_reliance; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.assessment_policy_reliance (id, assessment_id, risk_category_id, policy_chunk_id, decision, decided_by_user_id, decided_at) FROM stdin;
85b5c2ab-20cf-4571-a4b6-62bc9111fe80	9cf350cf-b9d2-4b1e-8f49-4661be9594bb	22222222-2222-2222-2222-222222222222	e7a09ebd-9c1f-4779-8499-fa131c4a77c4	ReliedUpon	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-22 15:35:56.593559+00
f7333518-43db-4eb6-b77f-ac1c6288ec26	9cf350cf-b9d2-4b1e-8f49-4661be9594bb	22222222-2222-2222-2222-222222222224	539e307e-5d18-454b-a33c-fbcf3ff8c407	ReliedUpon	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-22 15:42:20.114611+00
8f22856c-a71b-4871-a843-420e910d1542	bcef5b36-6d28-4778-8653-4ea2b2798edf	22222222-2222-2222-2222-222222222221	3f171e93-f2ca-40a4-af6a-18ede9021c9b	ReliedUpon	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-24 17:32:13.877552+00
dfe6cf7b-3c52-455a-bb8a-3ac4cccef494	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	22222222-2222-2222-2222-222222222222	e7a09ebd-9c1f-4779-8499-fa131c4a77c4	ReliedUpon	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 06:54:03.907812+00
7a25a613-aeaa-4956-b361-914625c6ff96	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	22222222-2222-2222-2222-222222222222	af07f40f-b9fa-4614-891b-b0fcc9a8f54b	NotRelevant	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 06:54:04.20961+00
d4d2b7eb-35a9-41d7-9246-11a9679e421e	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	22222222-2222-2222-2222-222222222222	3f171e93-f2ca-40a4-af6a-18ede9021c9b	ReliedUpon	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 06:58:55.039924+00
4baaf28d-33f5-470d-9984-1b647d4806a1	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	22222222-2222-2222-2222-222222222223	539e307e-5d18-454b-a33c-fbcf3ff8c407	ReliedUpon	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 06:58:55.32633+00
8468f45e-76f4-46c5-b094-1634ff2f594e	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	22222222-2222-2222-2222-222222222224	8fc9b915-62af-410e-af73-373e51aac522	ReliedUpon	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 06:58:55.614744+00
a27f811d-1d1d-4b0d-ba10-eec409ae9fba	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	22222222-2222-2222-2222-222222222222	af07f40f-b9fa-4614-891b-b0fcc9a8f54b	NotRelevant	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 06:58:55.904231+00
4700c463-24f8-4619-9951-ba294141373a	12f0ad4a-87e9-494c-924e-20be52169763	22222222-2222-2222-2222-222222222222	3f171e93-f2ca-40a4-af6a-18ede9021c9b	ReliedUpon	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 06:58:59.399046+00
3331b301-8ecc-4984-ab8e-bbf4cf57e72a	1de4b6d9-bc92-441c-8299-fe6b4d9fcc2e	22222222-2222-2222-2222-222222222222	af07f40f-b9fa-4614-891b-b0fcc9a8f54b	ReliedUpon	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 07:12:04.856541+00
dd0edbb8-1852-48e5-814e-319bd2f44f18	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	22222222-2222-2222-2222-222222222222	3f171e93-f2ca-40a4-af6a-18ede9021c9b	ReliedUpon	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 07:22:40.963481+00
13789a14-dbae-4c63-bb86-9043d5e273ab	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	22222222-2222-2222-2222-222222222223	539e307e-5d18-454b-a33c-fbcf3ff8c407	ReliedUpon	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 07:22:41.280105+00
e215d692-fa83-4f3e-8be6-58731f580516	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	22222222-2222-2222-2222-222222222224	8fc9b915-62af-410e-af73-373e51aac522	ReliedUpon	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 07:22:41.579402+00
ee986728-74a5-4b0e-9649-8772ffaabb96	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	22222222-2222-2222-2222-222222222222	af07f40f-b9fa-4614-891b-b0fcc9a8f54b	NotRelevant	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 07:22:41.887079+00
fa89511e-927e-4f91-b3a4-1168a983f4ba	50f965f9-70e5-4c4d-bec5-36017302898e	22222222-2222-2222-2222-222222222222	3f171e93-f2ca-40a4-af6a-18ede9021c9b	ReliedUpon	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 07:22:44.989794+00
1c5e9549-f939-4833-b6b9-485611b34fd7	a46d7e97-e303-4945-bf55-5ff7405b2a25	22222222-2222-2222-2222-222222222222	e7a09ebd-9c1f-4779-8499-fa131c4a77c4	ReliedUpon	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 07:26:43.740565+00
821b3477-5ac0-4edc-afea-bb3e8fdb2ea7	a46d7e97-e303-4945-bf55-5ff7405b2a25	22222222-2222-2222-2222-222222222224	539e307e-5d18-454b-a33c-fbcf3ff8c407	ReliedUpon	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 07:26:45.490252+00
e7e1450c-4999-4099-8429-3890cb6ae16b	a46d7e97-e303-4945-bf55-5ff7405b2a25	22222222-2222-2222-2222-222222222223	79e625c1-e99c-43d0-9c93-4f2ee8b6f914	ReliedUpon	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 07:26:46.82065+00
766fd40e-fbcb-45d9-9689-de5052f9ade6	9534f3f0-685a-4450-bfc0-983f2d16f7d9	22222222-2222-2222-2222-222222222222	3f171e93-f2ca-40a4-af6a-18ede9021c9b	ReliedUpon	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-28 08:00:56.714166+00
06688e6b-73bb-4eda-beda-40dbce2d26d1	9534f3f0-685a-4450-bfc0-983f2d16f7d9	22222222-2222-2222-2222-222222222223	539e307e-5d18-454b-a33c-fbcf3ff8c407	ReliedUpon	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-28 08:00:57.025116+00
6d748489-b0ba-4211-bfd5-911b2365069b	9534f3f0-685a-4450-bfc0-983f2d16f7d9	22222222-2222-2222-2222-222222222224	8fc9b915-62af-410e-af73-373e51aac522	ReliedUpon	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-28 08:00:57.337258+00
6422fce4-2023-41e4-9c57-ad839bcc0218	9534f3f0-685a-4450-bfc0-983f2d16f7d9	22222222-2222-2222-2222-222222222222	af07f40f-b9fa-4614-891b-b0fcc9a8f54b	NotRelevant	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-28 08:00:57.645695+00
71b44dfc-dbfe-4cea-97ca-fe0d72a1ace0	90b8631a-dba0-43a1-b722-92176fd4bd13	22222222-2222-2222-2222-222222222222	3f171e93-f2ca-40a4-af6a-18ede9021c9b	ReliedUpon	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-28 08:01:00.922567+00
6cd74099-ccbc-4699-aefd-f45423aaf769	fe6f95b7-3a35-4799-9eb2-e3239a6a3674	22222222-2222-2222-2222-222222222222	e7a09ebd-9c1f-4779-8499-fa131c4a77c4	ReliedUpon	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-28 08:05:41.654158+00
be4c6fdb-4452-4ef0-b93b-8f9d8aac2fe8	fe6f95b7-3a35-4799-9eb2-e3239a6a3674	22222222-2222-2222-2222-222222222224	539e307e-5d18-454b-a33c-fbcf3ff8c407	ReliedUpon	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-28 08:05:43.166572+00
44bcc9d2-5546-4be4-aee0-1c726f94b5d3	fe6f95b7-3a35-4799-9eb2-e3239a6a3674	22222222-2222-2222-2222-222222222223	79e625c1-e99c-43d0-9c93-4f2ee8b6f914	ReliedUpon	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-28 08:05:44.337023+00
d7b23eae-4c0a-4c3d-96ad-4dfa62d59b83	1887751d-52fb-4229-b25e-a1a2204df89c	22222222-2222-2222-2222-222222222222	3f171e93-f2ca-40a4-af6a-18ede9021c9b	ReliedUpon	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-29 08:14:22.854733+00
f6337036-f3dc-42ff-a906-caa2ee9746b6	1887751d-52fb-4229-b25e-a1a2204df89c	22222222-2222-2222-2222-222222222224	3f171e93-f2ca-40a4-af6a-18ede9021c9b	ReliedUpon	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-29 08:14:23.364598+00
05f8335b-d14c-44f3-abba-b68fca752941	1887751d-52fb-4229-b25e-a1a2204df89c	\N	3f171e93-f2ca-40a4-af6a-18ede9021c9b	ReliedUpon	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-29 08:14:24.304595+00
bf9bb4a1-58d0-4feb-aba4-76650c050dea	6e3cb87c-89cf-41ae-9629-15e5ae88b2ca	\N	3f171e93-f2ca-40a4-af6a-18ede9021c9b	ReliedUpon	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-30 12:12:09.504099+00
f8851649-f53e-42d1-8a5e-5f505485f755	6e3cb87c-89cf-41ae-9629-15e5ae88b2ca	22222222-2222-2222-2222-222222222222	4a27362f-c3e9-48a6-8e7d-538ca56e56a3	ReliedUpon	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-30 12:15:52.469383+00
909d3030-9b63-4f9a-ae7a-a4f40d366480	386b9113-a53e-4b90-a396-35e574b2bfa3	22222222-2222-2222-2222-222222222222	e7a09ebd-9c1f-4779-8499-fa131c4a77c4	ReliedUpon	4fa322d3-2245-44ef-b664-1a804442db23	2026-10-05 09:19:20.208628+00
333d04f7-1549-4ec1-9a40-db4253be21c9	386b9113-a53e-4b90-a396-35e574b2bfa3	22222222-2222-2222-2222-222222222222	4f51dd86-f2b8-41c7-88ad-2d44e8a295c2	NotRelevant	4fa322d3-2245-44ef-b664-1a804442db23	2026-10-05 09:19:23.244867+00
8823ad55-aa8f-47f3-8d4c-8a7721601a16	b2a913c6-c962-4dfd-9961-810e58affc32	22222222-2222-2222-2222-222222222221	3f171e93-f2ca-40a4-af6a-18ede9021c9b	ReliedUpon	4fa322d3-2245-44ef-b664-1a804442db23	2026-10-05 09:26:40.845797+00
\.


--
-- Data for Name: assessment_risk_score; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.assessment_risk_score (id, assessment_id, risk_category_id, inherent_rating, control_ids_credited, control_effectiveness, mitigation_factor_applied, residual_rating, is_override, override_reason, scored_by, created_by_user_id, created_at) FROM stdin;
0e3654c1-40b8-4bec-8cba-2bd5c6ae3297	9cf350cf-b9d2-4b1e-8f49-4661be9594bb	22222222-2222-2222-2222-222222222224	4.00	[]	0.000	0.850	4.00	f	\N	System	\N	2026-09-22 15:41:32.629145+00
6ef09b88-c392-4552-91b6-bd3f30e89d02	9cf350cf-b9d2-4b1e-8f49-4661be9594bb	22222222-2222-2222-2222-222222222222	5.00	[]	0.000	0.850	4.50	t	Slightly reducing from system-calculated 5.0 to 4.5 - vendor DD call confirmed a SOC 2 audit is in progress (not yet certified but underway), partial mitigating factor not captured by the control model.	System	\N	2026-09-22 15:41:31.824336+00
36e76183-2664-4437-9051-02ca7f5d2361	bcef5b36-6d28-4778-8653-4ea2b2798edf	22222222-2222-2222-2222-222222222221	4.00	[]	0.600	0.850	3.49	f	\N	System	\N	2026-09-24 17:32:37.689187+00
40f4db9e-eeeb-4d77-8c2d-a376dc30e764	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	22222222-2222-2222-2222-222222222223	1.00	[]	1.000	0.850	0.15	f	\N	System	\N	2026-09-25 06:54:31.678708+00
fc27ab2b-3596-45a8-ba46-3cac9bebe5af	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	22222222-2222-2222-2222-222222222224	3.00	[]	0.500	0.850	2.58	f	\N	System	\N	2026-09-25 06:54:32.014593+00
bd155f09-5e5a-46cb-85c6-a44b5f0e2ae6	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	22222222-2222-2222-2222-222222222222	4.00	[]	0.800	0.850	0.50	t	QA lock test	System	\N	2026-09-25 06:54:31.353231+00
8bef85f3-900b-4b73-b72d-d0142ec855f0	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	22222222-2222-2222-2222-222222222223	1.00	[]	1.000	0.850	0.15	f	\N	System	\N	2026-09-25 06:59:25.506723+00
dec88b7a-7ddc-4f30-ae24-a0bef4224a17	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	22222222-2222-2222-2222-222222222224	3.00	[]	0.500	0.850	2.58	f	\N	System	\N	2026-09-25 06:59:25.837855+00
8b677411-ad1b-48fe-bccb-2b524cd36409	386b9113-a53e-4b90-a396-35e574b2bfa3	22222222-2222-2222-2222-222222222222	3.00	[]	0.500	0.850	2.58	f	\N	System	\N	2026-10-05 09:39:03.041304+00
c3971a0f-a1bd-41ab-b492-4837be759859	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	22222222-2222-2222-2222-222222222222	4.00	[]	0.800	0.850	0.50	t	QA lock test	System	\N	2026-09-25 06:59:25.180503+00
f964fe77-b79e-4968-ae69-640a6affc476	d434153a-e47d-42e2-9009-b9390394d50b	22222222-2222-2222-2222-222222222222	3.00	[]	1.000	0.800	2.20	f	\N	System	\N	2026-09-25 07:02:21.764497+00
6c09555b-b68a-47b2-b681-00a10e438a48	1de4b6d9-bc92-441c-8299-fe6b4d9fcc2e	22222222-2222-2222-2222-222222222223	3.00	[]	0.500	0.850	2.58	f	\N	System	\N	2026-09-25 07:13:13.701396+00
46bd005e-9d1b-4ade-b319-c2397b25913d	1de4b6d9-bc92-441c-8299-fe6b4d9fcc2e	22222222-2222-2222-2222-222222222222	5.00	[]	1.000	0.850	2.50	t	Vendor had prior regulatory findings (QA)	System	\N	2026-09-25 07:13:12.518319+00
1912a7b8-c573-4f2e-a1e0-8f2b5d498f2f	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	22222222-2222-2222-2222-222222222223	1.00	[]	1.000	0.850	0.15	f	\N	System	\N	2026-09-25 07:23:11.046329+00
81dd2e07-f2e3-4eb3-901d-101e14fb51b8	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	22222222-2222-2222-2222-222222222224	3.00	[]	0.500	0.850	2.58	f	\N	System	\N	2026-09-25 07:23:11.382468+00
3979d7dd-8ddd-491a-a527-46bfe451cb99	e58102ff-6105-4be7-8f8a-befe3c0167ac	22222222-2222-2222-2222-222222222222	3.00	[]	0.500	0.800	2.60	f	\N	System	\N	2026-10-05 09:39:04.486728+00
c3ce38ba-bbcb-41e2-b277-d745d739d730	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	22222222-2222-2222-2222-222222222222	4.00	[]	0.800	0.850	0.50	t	QA lock test	System	\N	2026-09-25 07:23:10.717857+00
2efc8859-1b96-4beb-85fc-a1ff7036ba88	416b67b7-55af-4246-b3e1-22ef35c2202a	22222222-2222-2222-2222-222222222222	3.00	[]	1.000	0.800	2.20	f	\N	System	\N	2026-09-25 07:23:48.35413+00
0cb580e5-2551-45c2-9b2f-7303b60ed4b6	a46d7e97-e303-4945-bf55-5ff7405b2a25	22222222-2222-2222-2222-222222222224	3.00	[]	0.500	0.850	2.58	f	\N	System	\N	2026-09-25 07:28:16.907935+00
c5f1159c-e715-4f4c-af85-04f4819fe3eb	a46d7e97-e303-4945-bf55-5ff7405b2a25	22222222-2222-2222-2222-222222222223	3.00	[]	0.500	0.850	2.58	f	\N	System	\N	2026-09-25 07:28:17.537736+00
dcd47fb3-16a0-47e9-9074-cf8abbe1735d	a46d7e97-e303-4945-bf55-5ff7405b2a25	22222222-2222-2222-2222-222222222222	5.00	[]	1.000	0.850	2.50	t	Vendor had prior regulatory findings (QA)	System	\N	2026-09-25 07:28:15.762956+00
f3d226e4-791f-4c55-8789-11757b9595c7	9534f3f0-685a-4450-bfc0-983f2d16f7d9	22222222-2222-2222-2222-222222222223	1.00	[]	1.000	0.850	0.15	f	\N	System	\N	2026-09-28 08:01:34.315434+00
4f316764-37c7-448c-975c-b4868a164853	9534f3f0-685a-4450-bfc0-983f2d16f7d9	22222222-2222-2222-2222-222222222224	3.00	[]	0.500	0.850	2.58	f	\N	System	\N	2026-09-28 08:01:34.672233+00
084b8a1f-26d9-4a7a-a0f8-f8b0dd964f87	9534f3f0-685a-4450-bfc0-983f2d16f7d9	22222222-2222-2222-2222-222222222222	4.00	[]	0.800	0.850	0.50	t	QA lock test	System	\N	2026-09-28 08:01:33.976207+00
b9112532-ef77-485f-a8bc-aa20b58970f4	fef65e9f-675f-4a97-bed4-ab32decd986a	22222222-2222-2222-2222-222222222222	3.00	[]	1.000	0.800	2.20	f	\N	System	\N	2026-09-28 08:02:15.295051+00
cb339489-16bb-4e49-a0a2-14f8267f6537	fe6f95b7-3a35-4799-9eb2-e3239a6a3674	22222222-2222-2222-2222-222222222224	3.00	[]	0.500	0.850	2.58	f	\N	System	\N	2026-09-28 08:07:02.002292+00
94cb527c-9be1-4297-b724-5d014f6a5632	fe6f95b7-3a35-4799-9eb2-e3239a6a3674	22222222-2222-2222-2222-222222222223	3.00	[]	0.500	0.850	2.58	f	\N	System	\N	2026-09-28 08:07:03.114893+00
ab482d8a-12cb-4dfb-985d-0ab80248da75	fe6f95b7-3a35-4799-9eb2-e3239a6a3674	22222222-2222-2222-2222-222222222222	5.00	[]	1.000	0.850	2.50	t	Vendor had prior regulatory findings (QA)	System	\N	2026-09-28 08:07:00.896623+00
c2cb451b-6603-4562-9929-bba492469b1c	6e3cb87c-89cf-41ae-9629-15e5ae88b2ca	22222222-2222-2222-2222-222222222221	4.00	["76333a56-763e-4ea4-938c-a97d372a91de", "f2e10b03-e672-42da-9295-9093b5a6fd84"]	0.600	0.850	3.49	f	\N	System	\N	2026-09-30 12:45:44.753631+00
0de5b7f2-5e12-4a5e-9754-40d7cc58bc22	6e3cb87c-89cf-41ae-9629-15e5ae88b2ca	22222222-2222-2222-2222-222222222222	3.00	["f2454cd8-2368-43db-ad6d-fd797f6ffc2c", "46977ebe-4d9e-47ae-b9dc-c11f6959fafd"]	0.650	0.850	2.45	f	\N	System	\N	2026-09-30 12:46:34.907676+00
7c7bcae2-197d-48d3-96da-9a9673a4138a	6e3cb87c-89cf-41ae-9629-15e5ae88b2ca	22222222-2222-2222-2222-222222222223	4.00	["af3a916f-bd80-46ed-9589-2f482e6a2b57", "bfb124c8-b49b-442b-919a-f410b62d5101"]	0.700	0.850	3.41	f	\N	System	\N	2026-09-30 12:47:00.318032+00
0469fc35-fb26-4a05-8385-d92cbedbf4a6	b2a913c6-c962-4dfd-9961-810e58affc32	22222222-2222-2222-2222-222222222221	1.00	["76333a56-763e-4ea4-938c-a97d372a91de", "f2e10b03-e672-42da-9295-9093b5a6fd84", "c0e2f410-3642-469a-94d2-f9d8eac0b2b2", "7ee7aaa5-4b80-4304-a149-7aa95e7c57b6"]	1.000	0.850	2.20	t	QA-FT 05Oct: prepaid limits verified in pilot; analyst judgement lowers residual	Analyst	\N	2026-10-05 09:24:18.675111+00
\.


--
-- Data for Name: audit_event; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.audit_event (id, change_request_id, assessment_id, entity_type, entity_id, action, actor_user_id, actor_label, before_value, after_value, reason, created_at) FROM stdin;
c1ebf0ee-a715-440e-9c56-2127e495a1fc	8400daf2-14ec-489a-878f-2053e67a1d31	\N	ChangeRequest	8400daf2-14ec-489a-878f-2053e67a1d31	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "Azure DB e2e verification test", "status": "Submitted", "changeType": "Process"}	\N	2026-09-22 14:13:48.366072+00
0f28fe5f-54c7-4bfa-bc71-fde083cebae1	8400daf2-14ec-489a-878f-2053e67a1d31	\N	Attachment	4e2ef96e-3461-4035-8db2-901f5a0a11e0	Uploaded	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"version": 1, "fileName": "blob-test.docx"}	\N	2026-09-22 14:57:54.098265+00
5087721a-622e-4ead-91a9-af79fa339533	87057aee-66d0-4eed-b503-ee593be28113	\N	ChangeRequest	87057aee-66d0-4eed-b503-ee593be28113	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "Onboard QuickPay Processing for card settlement", "status": "Submitted", "changeType": "Vendor"}	\N	2026-09-22 15:32:14.491609+00
03057a4e-ac8e-4679-b7c6-6aaec7c148bf	87057aee-66d0-4eed-b503-ee593be28113	\N	ExternalSnapshot	87057aee-66d0-4eed-b503-ee593be28113	Ingested	\N	system	\N	{"hasVendor": true, "hasProduct": false, "hasCustomer": false}	\N	2026-09-22 15:32:15.281747+00
c49e505b-f438-44d2-8df0-99a5463bee74	87057aee-66d0-4eed-b503-ee593be28113	\N	Attachment	d0e2c4f6-3ecf-4088-bc65-aa0eb0ee5528	Uploaded	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"version": 1, "fileName": "quickpay-vendor-dd.docx"}	\N	2026-09-22 15:34:14.18654+00
0a8dd60f-83d6-4957-a7e0-c498e49ea0b5	\N	9cf350cf-b9d2-4b1e-8f49-4661be9594bb	CategoryMapping	1cb87792-6f07-4bf0-8973-8f4722aa6add	AiProposed	\N	system/AI	\N	{"citation": "FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Customers", "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	\N	2026-09-22 15:34:33.256392+00
d03b0630-6d35-4751-bff9-0282d35db99d	\N	9cf350cf-b9d2-4b1e-8f49-4661be9594bb	CategoryMapping	08034967-bfce-49a7-997b-37af38785140	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"isActive": true, "riskCategoryId": "22222222-2222-2222-2222-222222222224"}	Third-party vendor with full transaction data access is itself a delivery-channel risk per FFIEC guidance - AI proposal missed this, adding per CLAUDE.md's vendor-onboarding mapping table.	2026-09-22 15:34:49.136386+00
de56fa15-679b-4c2b-adff-93be3ce6fef5	\N	9cf350cf-b9d2-4b1e-8f49-4661be9594bb	PolicyReliance	85b5c2ab-20cf-4571-a4b6-62bc9111fe80	Decided	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"decision": "ReliedUpon", "policyChunkId": "e7a09ebd-9c1f-4779-8499-fa131c4a77c4"}	\N	2026-09-22 15:35:56.593559+00
8b31fec6-7975-4fc3-a1e5-c438350d07eb	87057aee-66d0-4eed-b503-ee593be28113	\N	ExtractedField	9bc6209e-b918-44e8-bb93-4bda2e6a131c	AiExtracted	\N	system/AI	\N	{"value": "QuickPay Processing LLC", "fieldKey": "vendor_name", "confidence": 1, "needsReview": false}	\N	2026-09-22 15:39:44.459448+00
75874c1c-1812-4590-9ce4-c031d223c51a	87057aee-66d0-4eed-b503-ee593be28113	\N	ExtractedField	c324f74f-4f37-4698-8e50-1dd81d933e18	AiExtracted	\N	system/AI	\N	{"value": "Cayman Islands", "fieldKey": "vendor_jurisdiction", "confidence": 1, "needsReview": false}	\N	2026-09-22 15:39:44.834102+00
f0390c2e-c180-4617-8675-506b5c48a8f6	87057aee-66d0-4eed-b503-ee593be28113	\N	ExtractedField	e95fdbbc-d490-456e-99c8-cf23d29734c7	AiExtracted	\N	system/AI	\N	{"value": "Full transaction data, card PANs", "fieldKey": "data_access_scope", "confidence": 1, "needsReview": false}	\N	2026-09-22 15:39:45.139701+00
727298e5-d511-4c7f-b432-f597827ca59d	87057aee-66d0-4eed-b503-ee593be28113	\N	ExtractedField	e95fdbbc-d490-456e-99c8-cf23d29734c7	Corrected	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "e95fdbbc-d490-456e-99c8-cf23d29734c7", "source": "AiExtracted", "field_key": "data_access_scope", "confidence": 1.000, "updated_at": "2026-09-22T15:39:45.139701+00:00", "field_value": "Full transaction data, card PANs", "needs_review": false, "attachment_id": "d0e2c4f6-3ecf-4088-bc65-aa0eb0ee5528", "source_excerpt": "Data access scope: Full transaction data, card PANs", "change_request_id": "87057aee-66d0-4eed-b503-ee593be28113", "updated_by_user_id": null}	{"value": "Full transaction data, card PANs, and cardholder PII", "fieldKey": "data_access_scope"}	Vendor DD call on 2026-09-22 confirmed scope also includes cardholder PII, not just PANs - document understated scope.	2026-09-22 15:40:27.619131+00
c865b75f-c7e8-4317-a0f4-b3ce8d194c27	\N	9cf350cf-b9d2-4b1e-8f49-4661be9594bb	NarrativeSection	c957bc7f-31f3-4c6a-8917-ab3233c86fd2	AiDrafted	\N	system/AI	\N	{"text": "The proposed onboarding of QuickPay Processing LLC as a vendor to process full transaction data and card primary account numbers (PANs) for our new prepaid settlement flow involves considerations relevant to elevated money laundering risk. According to the FFIEC BSA/AML Manual, certain customers and entities, including those operating in higher-risk jurisdictions and industries, require enhanced scrutiny under a risk-based customer due diligence framework (Risks Associated with Money Laundering and Terrorist Financing - Customers). QuickPay Processing LLC is based in the Cayman Islands, which necessitates a careful assessment of their money laundering and terrorist financing risk profile due to the jurisdiction's heightened risk factors. Additionally, the vendor will have access to sensitive cardholder personally identifiable information (PII), which further underscores the importance of diligent controls and oversight. Given the lack of a compliance certification on file for QuickPay Processing LLC, the institution must ensure adequate due diligence and risk mitigation procedures are established so that the vendor's role aligns with the bank's broader financial crimes risk management policies.", "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	\N	2026-09-22 15:40:44.589321+00
3506d316-8479-4852-a4ca-ac5ae9a3093d	\N	9cf350cf-b9d2-4b1e-8f49-4661be9594bb	NarrativeSection	49a04fe9-4b96-4537-b649-f2804151f911	AiDrafted	\N	system/AI	\N	{"text": "The proposed business change involves onboarding QuickPay Processing LLC, a vendor based in the Cayman Islands, to process full transaction data and card PANs for the new prepaid settlement flow. This introduces delivery channel risks associated with utilizing a third-party processor in a foreign jurisdiction without a current compliance certification on file. Given the significant scope of data access, including cardholder personally identifiable information (PII), there is an elevated risk of money laundering and terrorist financing that must be mitigated through enhanced due diligence and ongoing oversight.\\n\\nAccording to the FFIEC BSA/AML Manual section on Risks Associated with Money Laundering and Terrorist Financing: Products and Services (Delivery Channels), the use of remote or less transparent delivery channels such as third-party vendors in offshore jurisdictions requires comprehensive risk assessment and controls to manage potential vulnerabilities. The lack of compliance certification for QuickPay Processing LLC further intensifies these risks, underscoring the need for thorough vendor risk management practices before full integration into the bank's prepaid settlement processes.", "riskCategoryId": "22222222-2222-2222-2222-222222222224"}	\N	2026-09-22 15:40:52.219987+00
fa79e29b-8268-4079-ab0c-201a9e1846d6	\N	9cf350cf-b9d2-4b1e-8f49-4661be9594bb	NarrativeSection	c957bc7f-31f3-4c6a-8917-ab3233c86fd2	AnalystReviewed	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"status": "AnalystReviewed", "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	\N	2026-09-22 15:41:04.659102+00
911fe516-1089-4049-9e84-8e839720af5e	\N	9cf350cf-b9d2-4b1e-8f49-4661be9594bb	NarrativeSection	49a04fe9-4b96-4537-b649-f2804151f911	AnalystReviewed	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"status": "AnalystReviewed", "riskCategoryId": "22222222-2222-2222-2222-222222222224"}	\N	2026-09-22 15:41:05.114551+00
ae4b658d-20b9-4184-8eba-cdcc8c13433c	\N	9cf350cf-b9d2-4b1e-8f49-4661be9594bb	RiskScore	6ef09b88-c392-4552-91b6-bd3f30e89d02	Calculated	\N	system/AI	\N	{"inherent": 5, "residual": 5.000, "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	\N	2026-09-22 15:41:31.824336+00
d2c0d50f-8c96-47fb-964c-c81b0ae7598e	\N	9cf350cf-b9d2-4b1e-8f49-4661be9594bb	RiskScore	0e3654c1-40b8-4bec-8cba-2bd5c6ae3297	Calculated	\N	system/AI	\N	{"inherent": 4, "residual": 4.000, "riskCategoryId": "22222222-2222-2222-2222-222222222224"}	\N	2026-09-22 15:41:32.629145+00
0e48d7a0-4034-4851-85a9-84cd3d30f4a2	1d6e0018-0dbe-4b67-b4ae-eb80a828c493	\N	ChangeRequest	1d6e0018-0dbe-4b67-b4ae-eb80a828c493	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609250649] type Vendor", "status": "Submitted", "changeType": "Vendor"}	\N	2026-09-25 06:49:23.85048+00
438225cd-52f4-4c0b-89f4-509b1d729bc8	\N	9cf350cf-b9d2-4b1e-8f49-4661be9594bb	RiskScore	6ef09b88-c392-4552-91b6-bd3f30e89d02	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "6ef09b88-c392-4552-91b6-bd3f30e89d02", "scored_by": "System", "created_at": "2026-09-22T15:41:31.824336+00:00", "is_override": false, "assessment_id": "9cf350cf-b9d2-4b1e-8f49-4661be9594bb", "inherent_rating": 5.00, "override_reason": null, "residual_rating": 5.00, "risk_category_id": "22222222-2222-2222-2222-222222222222", "created_by_user_id": null, "control_ids_credited": [], "control_effectiveness": 0.000, "mitigation_factor_applied": 0.850}	{"residual": 4.5, "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	Slightly reducing from system-calculated 5.0 to 4.5 - vendor DD call confirmed a SOC 2 audit is in progress (not yet certified but underway), partial mitigating factor not captured by the control model.	2026-09-22 15:41:43.124333+00
3e3f6545-18d6-4d40-b3ca-8e4a9c032f26	\N	9cf350cf-b9d2-4b1e-8f49-4661be9594bb	PolicyReliance	f7333518-43db-4eb6-b77f-ac1c6288ec26	Decided	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"decision": "ReliedUpon", "policyChunkId": "539e307e-5d18-454b-a33c-fbcf3ff8c407"}	\N	2026-09-22 15:42:20.114611+00
34e22c82-c619-4c12-b880-ca20c81d3b18	87057aee-66d0-4eed-b503-ee593be28113	9cf350cf-b9d2-4b1e-8f49-4661be9594bb	Assessment	9cf350cf-b9d2-4b1e-8f49-4661be9594bb	Finalized	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"finalizedBy": "4fa322d3-2245-44ef-b664-1a804442db23"}	\N	2026-09-22 15:42:31.944065+00
90a9fccb-84c2-4a95-a8a2-829a008772eb	87057aee-66d0-4eed-b503-ee593be28113	9cf350cf-b9d2-4b1e-8f49-4661be9594bb	ChangeRequest	87057aee-66d0-4eed-b503-ee593be28113	Routed	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"status": "PendingCommittee"}	\N	2026-09-22 15:43:01.379101+00
15bc1bb7-7b9a-4bf1-805f-316e28a5c39d	87057aee-66d0-4eed-b503-ee593be28113	9cf350cf-b9d2-4b1e-8f49-4661be9594bb	CommitteeVote	46525f86-18fe-4883-8d76-f54a6be546a2	Voted	083ecfe5-aa01-4703-9168-762f0065078f	human	\N	{"vote": "ApproveWithConditions", "rationale": null, "conditionsText": "Vendor must obtain SOC 2 Type II certification within 90 days of go-live; quarterly compliance attestation required for the first year."}	\N	2026-09-22 15:43:17.419501+00
79fbd4b6-9df0-4dd9-96e3-1e86d898c74f	87057aee-66d0-4eed-b503-ee593be28113	9cf350cf-b9d2-4b1e-8f49-4661be9594bb	CommitteeVote	8c429502-e0c7-4db6-9870-03db402ef3db	Voted	fa142c1c-58cc-4666-b135-7768a2ab33f0	human	\N	{"vote": "Approve", "rationale": null, "conditionsText": null}	\N	2026-09-22 15:43:19.714584+00
132cdcbb-8049-46e8-844a-c24d5541c3ee	87057aee-66d0-4eed-b503-ee593be28113	9cf350cf-b9d2-4b1e-8f49-4661be9594bb	CommitteeDecision	ed0c9443-9dbe-414b-80d5-bbbd2417021b	Decisioned	\N	system/AI	\N	{"resolution": "ApprovedWithConditions", "conditionsText": "Jordan Blake: Vendor must obtain SOC 2 Type II certification within 90 days of go-live; quarterly compliance attestation required for the first year."}	\N	2026-09-22 15:43:21.169626+00
f961253b-d6be-42f8-96d3-2261dedd282a	87057aee-66d0-4eed-b503-ee593be28113	\N	MockSystemsFeedback	87057aee-66d0-4eed-b503-ee593be28113	Pushed	\N	system	\N	{"goLive": true, "resolution": "ApprovedWithConditions", "ratingSummary": "Approved with conditions: Jordan Blake: Vendor must obtain SOC 2 Type II certification within 90 days of go-live; quarterly compliance attestation required for the first year."}	\N	2026-09-22 15:43:24.774423+00
ae4af5f3-126b-42c4-9186-b5cf4dbafdd9	bd7b9737-77c8-4564-8a78-2d64ba3060a3	\N	ChangeRequest	bd7b9737-77c8-4564-8a78-2d64ba3060a3	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "AzureFoundry E2E Test - Prepaid Card Launch", "status": "Submitted", "changeType": "Product"}	\N	2026-09-24 17:19:42.292795+00
5d7baa20-a843-4aca-ba12-178debab0a24	\N	bcef5b36-6d28-4778-8653-4ea2b2798edf	CategoryMapping	b9ddd204-0a1b-4789-90c4-83519bd4d76c	AiProposed	\N	system/AI	\N	{"citation": "FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Products and Services", "riskCategoryId": "22222222-2222-2222-2222-222222222221"}	\N	2026-09-24 17:20:00.84284+00
ee1efae1-4378-4a29-85eb-c49a3bd17a29	\N	bcef5b36-6d28-4778-8653-4ea2b2798edf	PolicyReliance	8f22856c-a71b-4871-a843-420e910d1542	Decided	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"decision": "ReliedUpon", "policyChunkId": "3f171e93-f2ca-40a4-af6a-18ede9021c9b"}	\N	2026-09-24 17:32:13.877552+00
105f68c1-612a-4dcd-b61b-0e023d83c37b	\N	bcef5b36-6d28-4778-8653-4ea2b2798edf	NarrativeSection	3b8af7a7-200a-4623-907c-68c4610b07b4	AiDrafted	\N	system/AI	\N	{"text": "The proposed launch of the AzureFoundry E2E Test for a prepaid card product introduces inherent risks consistent with those identified in the FFIEC BSA/AML Manual concerning products and services vulnerable to money laundering and terrorist financing. Specifically, prepaid access products are noted for their susceptibility due to rapid movement of funds and the potential for limited face-to-face interactions, which may complicate customer verification and transaction monitoring processes. Prior to the launch of such products, it is essential that the bank has adequately identified, measured, and implemented effective controls to mitigate these risks, as outlined in the supervisory guidance (Risks Associated with Money Laundering and Terrorist Financing - Products and Services). Given the nature of the test involving an AI provider and category mapping, the bank should ensure that AML controls are integrated into the product's design and deployment to prevent exploitation by illicit actors.", "riskCategoryId": "22222222-2222-2222-2222-222222222221"}	\N	2026-09-24 17:32:25.297743+00
221ef976-6786-4ed7-9484-6ccd945bc4f3	\N	bcef5b36-6d28-4778-8653-4ea2b2798edf	NarrativeSection	3b8af7a7-200a-4623-907c-68c4610b07b4	AnalystReviewed	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"status": "AnalystReviewed", "riskCategoryId": "22222222-2222-2222-2222-222222222221"}	\N	2026-09-24 17:32:31.872682+00
40b4f1a6-8c7a-417e-88cb-86cfa084e750	\N	bcef5b36-6d28-4778-8653-4ea2b2798edf	RiskScore	36e76183-2664-4437-9051-02ca7f5d2361	Calculated	\N	system/AI	\N	{"inherent": 4, "residual": 3.4900, "riskCategoryId": "22222222-2222-2222-2222-222222222221"}	\N	2026-09-24 17:32:37.689187+00
23b487e0-7e4d-49f4-93fd-b494ab483eea	bd7b9737-77c8-4564-8a78-2d64ba3060a3	bcef5b36-6d28-4778-8653-4ea2b2798edf	Assessment	bcef5b36-6d28-4778-8653-4ea2b2798edf	Finalized	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"finalizedBy": "4fa322d3-2245-44ef-b664-1a804442db23"}	\N	2026-09-24 17:32:52.022436+00
3050bc7a-d638-4031-930b-d267d4e7cafe	bd7b9737-77c8-4564-8a78-2d64ba3060a3	bcef5b36-6d28-4778-8653-4ea2b2798edf	ChangeRequest	bd7b9737-77c8-4564-8a78-2d64ba3060a3	Routed	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"status": "PendingCommittee"}	\N	2026-09-24 17:32:57.887535+00
9a4f9d41-113e-4f15-80f5-af9cd1d06a3f	bd7b9737-77c8-4564-8a78-2d64ba3060a3	bcef5b36-6d28-4778-8653-4ea2b2798edf	CommitteeVote	1bb1a668-9bee-4b39-8c01-f4b287e86b44	Voted	083ecfe5-aa01-4703-9168-762f0065078f	human	\N	{"vote": "Approve", "rationale": null, "conditionsText": null}	\N	2026-09-24 17:33:04.712445+00
045704d4-04d0-4350-9b81-ac464322ce03	bd7b9737-77c8-4564-8a78-2d64ba3060a3	bcef5b36-6d28-4778-8653-4ea2b2798edf	CommitteeVote	38bc5b88-b1df-416a-978b-9de7a0b349d9	Voted	fa142c1c-58cc-4666-b135-7768a2ab33f0	human	\N	{"vote": "Approve", "rationale": null, "conditionsText": null}	\N	2026-09-24 17:33:12.182553+00
fb48a496-0a21-4bb9-9a90-0f0c9092565a	bd7b9737-77c8-4564-8a78-2d64ba3060a3	bcef5b36-6d28-4778-8653-4ea2b2798edf	CommitteeDecision	eb256c62-8d36-4b7c-a961-a56f89a98531	Decisioned	\N	system/AI	\N	{"resolution": "Approved", "conditionsText": null}	\N	2026-09-24 17:33:13.407376+00
30ec1252-cf64-4c45-9f93-4b9561ad96cf	\N	bcef5b36-6d28-4778-8653-4ea2b2798edf	CategoryMapping	b9ddd204-0a1b-4789-90c4-83519bd4d76c	AiProposed	\N	system/AI	\N	{"citation": "FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Products and Services", "riskCategoryId": "22222222-2222-2222-2222-222222222221"}	\N	2026-09-25 06:27:34.346294+00
3da958eb-161d-4ffa-bdc9-6f053868cc99	\N	bcef5b36-6d28-4778-8653-4ea2b2798edf	CategoryMapping	64284d0c-a39d-4d31-95c1-79aec6b6ed1a	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"isActive": true, "riskCategoryId": "22222222-2222-2222-2222-222222222224"}	2321sdasdas	2026-09-25 06:27:57.425607+00
14fb5266-6586-4f89-af14-6ddcd82717ea	fd8253fb-6283-4e71-9b9c-53bf0ca1790f	\N	ChangeRequest	fd8253fb-6283-4e71-9b9c-53bf0ca1790f	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609250649] API intake - prepaid card", "status": "Submitted", "changeType": "Product"}	\N	2026-09-25 06:49:22.047018+00
840c59ad-6cd3-4847-b51a-049e7b7f3d96	fd8253fb-6283-4e71-9b9c-53bf0ca1790f	\N	ExternalSnapshot	fd8253fb-6283-4e71-9b9c-53bf0ca1790f	Ingested	\N	system	\N	{"hasVendor": false, "hasProduct": true, "hasCustomer": false}	\N	2026-09-25 06:49:22.156129+00
4080ef28-12be-4af5-8570-26e91b9ddd15	7613c46e-1aa4-4260-8027-22e0114d760d	\N	ChangeRequest	7613c46e-1aa4-4260-8027-22e0114d760d	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609250649] type Product", "status": "Submitted", "changeType": "Product"}	\N	2026-09-25 06:49:22.990982+00
e72e9c79-d03c-4fe5-a72e-82be5eeef6d8	52b609f3-3f61-4b2e-9bfa-0e215555b5d5	\N	ChangeRequest	52b609f3-3f61-4b2e-9bfa-0e215555b5d5	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609250649] type Feature", "status": "Submitted", "changeType": "Feature"}	\N	2026-09-25 06:49:23.278225+00
5f40df71-6f08-4224-8760-8fd5af425fcd	09a5036e-ad3f-48ff-b2cf-fce2b8ada8e4	\N	ChangeRequest	09a5036e-ad3f-48ff-b2cf-fce2b8ada8e4	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609250649] type Process", "status": "Submitted", "changeType": "Process"}	\N	2026-09-25 06:49:23.566589+00
29793333-f307-4843-9d30-f3eb79aabda5	8d3e5920-b652-492a-8bfc-a267db3389d6	\N	ChangeRequest	8d3e5920-b652-492a-8bfc-a267db3389d6	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609250649] type Geography", "status": "Submitted", "changeType": "Geography"}	\N	2026-09-25 06:49:24.134701+00
ad3d5fa3-beec-4e50-b060-9b54cdf676f8	5bcb3b1d-d7cc-41a7-8d39-277aa7a76694	\N	ChangeRequest	5bcb3b1d-d7cc-41a7-8d39-277aa7a76694	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609250649] type CustomerSegment", "status": "Submitted", "changeType": "CustomerSegment"}	\N	2026-09-25 06:49:24.411171+00
d93de231-530d-49b6-ac73-8f40ad2d81e1	5de8ab3f-5c62-4f6a-a40b-360a6cabd8d1	\N	ChangeRequest	5de8ab3f-5c62-4f6a-a40b-360a6cabd8d1	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "", "status": "Submitted", "changeType": "Product"}	\N	2026-09-25 06:49:26.117233+00
e05b0d43-9584-4f22-beb7-6154b9deba9f	6dbe79eb-3aec-4d08-bcbf-f06873955cd1	\N	ChangeRequest	6dbe79eb-3aec-4d08-bcbf-f06873955cd1	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609250649] attachments", "status": "Submitted", "changeType": "Vendor"}	\N	2026-09-25 06:49:33.021022+00
66c2cf7e-32af-4913-9716-bb8101b10684	6dbe79eb-3aec-4d08-bcbf-f06873955cd1	\N	Attachment	56c30397-333c-4693-a798-f08a2721791b	Uploaded	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"version": 1, "fileName": "vendor-due-diligence.pdf"}	\N	2026-09-25 06:49:34.619423+00
78cd4f02-7f26-4c9a-8940-3b975c3aed46	6dbe79eb-3aec-4d08-bcbf-f06873955cd1	\N	Attachment	544b1759-8ec1-4a12-80ec-08978ea9f20c	Uploaded	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"version": 1, "fileName": "product-spec.docx"}	\N	2026-09-25 06:49:35.09969+00
867f72e6-3723-4c9f-b04f-d2f9bbf68623	6dbe79eb-3aec-4d08-bcbf-f06873955cd1	\N	Attachment	15321c25-11f0-4134-a4e3-bdbe3667ce2c	Uploaded	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"version": 1, "fileName": "control-matrix.xlsx"}	\N	2026-09-25 06:49:35.45411+00
ce4cde60-3abd-4ca0-a7d1-01ce6c51de88	caef4c84-30cc-40b5-9675-492cab0ee7a6	\N	ChangeRequest	caef4c84-30cc-40b5-9675-492cab0ee7a6	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609250649] bad uploads", "status": "Submitted", "changeType": "Vendor"}	\N	2026-09-25 06:49:37.716834+00
c2bb9ace-a14c-4e58-aef9-3270bda3afcd	caef4c84-30cc-40b5-9675-492cab0ee7a6	\N	Attachment	32bc8dd4-c804-460c-8a28-12a231e13ee3	Uploaded	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"version": 1, "fileName": "malicious.exe"}	\N	2026-09-25 06:49:38.556232+00
ec46b44e-3864-4f1f-8ad2-906b1108f7e1	5c23a789-398d-4685-bbf6-f4977f7c9d6f	\N	ChangeRequest	5c23a789-398d-4685-bbf6-f4977f7c9d6f	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609250649] clarification", "status": "Submitted", "changeType": "Geography"}	\N	2026-09-25 06:49:40.541984+00
cacfc980-019f-47bb-8530-32c835b83c36	5c23a789-398d-4685-bbf6-f4977f7c9d6f	\N	Clarification	8e661d25-f232-4a66-9031-23670b89c9aa	Requested	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"question": "Which target countries exactly?"}	\N	2026-09-25 06:49:40.87516+00
90f840a1-ad69-4fc0-8df9-5e4446eab7d4	e83eae48-d616-48ec-8947-e81e3bc4e0f3	\N	ChangeRequest	e83eae48-d616-48ec-8947-e81e3bc4e0f3	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609250649] snapshot linked", "status": "Submitted", "changeType": "Product"}	\N	2026-09-25 06:49:42.043857+00
347383ee-09a6-4974-ad02-0ff55a23256c	e83eae48-d616-48ec-8947-e81e3bc4e0f3	\N	ExternalSnapshot	e83eae48-d616-48ec-8947-e81e3bc4e0f3	Ingested	\N	system	\N	{"hasVendor": false, "hasProduct": true, "hasCustomer": false}	\N	2026-09-25 06:49:42.110195+00
dfcde955-ed58-4455-af94-409e2fab4c43	eee8de4f-c64c-436e-92b3-f9c85e7b3d91	\N	ChangeRequest	eee8de4f-c64c-436e-92b3-f9c85e7b3d91	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609250649] snapshot none", "status": "Submitted", "changeType": "Process"}	\N	2026-09-25 06:49:42.405273+00
8fc720d8-9473-4a45-8e9a-06255867f8eb	97305b4b-fdb8-418c-9987-3cfafcd1d1dd	\N	ChangeRequest	97305b4b-fdb8-418c-9987-3cfafcd1d1dd	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609250649] API intake - prepaid card", "status": "Submitted", "changeType": "Product"}	\N	2026-09-25 06:50:00.31761+00
84fbec89-3a10-42d4-b2a2-a85546a7d5cb	97305b4b-fdb8-418c-9987-3cfafcd1d1dd	\N	ExternalSnapshot	97305b4b-fdb8-418c-9987-3cfafcd1d1dd	Ingested	\N	system	\N	{"hasVendor": false, "hasProduct": true, "hasCustomer": false}	\N	2026-09-25 06:50:00.389203+00
547b7060-1d9e-4664-af70-9fdf1feea161	99fe5bab-2439-4d0e-8be6-20e5656ad100	\N	ChangeRequest	99fe5bab-2439-4d0e-8be6-20e5656ad100	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609250649] type Product", "status": "Submitted", "changeType": "Product"}	\N	2026-09-25 06:50:01.319542+00
cbaae96e-903d-4bc8-b93c-db44e99a2491	724a96ec-6d75-4ebd-9ed5-d15d7abcccca	\N	ChangeRequest	724a96ec-6d75-4ebd-9ed5-d15d7abcccca	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609250649] type Feature", "status": "Submitted", "changeType": "Feature"}	\N	2026-09-25 06:50:01.625912+00
4d9acdf0-2913-42f6-bbe3-b45fd792b584	24611c0a-41dc-4d53-a30d-d6b4b4cc1678	\N	ChangeRequest	24611c0a-41dc-4d53-a30d-d6b4b4cc1678	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609250649] type Process", "status": "Submitted", "changeType": "Process"}	\N	2026-09-25 06:50:01.925024+00
89167cc8-3070-49a3-b846-df8c9416d58c	b6547a00-7b54-49b6-b57f-7bef8b75019e	\N	ChangeRequest	b6547a00-7b54-49b6-b57f-7bef8b75019e	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609250649] type Vendor", "status": "Submitted", "changeType": "Vendor"}	\N	2026-09-25 06:50:02.225653+00
f25adf1c-23d5-42d2-8e95-f06c4d669fe0	cff8bed1-7fce-4d6e-a0bf-b23161306c4e	\N	ChangeRequest	cff8bed1-7fce-4d6e-a0bf-b23161306c4e	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609250649] type Geography", "status": "Submitted", "changeType": "Geography"}	\N	2026-09-25 06:50:02.519935+00
65251678-d63d-45a0-ae8f-7fab32c91483	1083ff18-0335-423f-9ae8-a735fe833302	\N	ChangeRequest	1083ff18-0335-423f-9ae8-a735fe833302	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609250649] type CustomerSegment", "status": "Submitted", "changeType": "CustomerSegment"}	\N	2026-09-25 06:50:02.805663+00
0c7521e0-ceed-42af-b199-90ba129e799c	506888b7-0548-4f31-91fc-8ee9d999bad0	\N	ChangeRequest	506888b7-0548-4f31-91fc-8ee9d999bad0	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "", "status": "Submitted", "changeType": "Product"}	\N	2026-09-25 06:50:04.552981+00
fe3f40c0-7e17-420e-af88-8f2a40d8f58c	3976f8cd-9fce-4858-b550-2ba02670603c	\N	ChangeRequest	3976f8cd-9fce-4858-b550-2ba02670603c	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609250649] attachments", "status": "Submitted", "changeType": "Vendor"}	\N	2026-09-25 06:50:11.579863+00
3a330153-0b92-4e22-b978-11e4d28745dd	3976f8cd-9fce-4858-b550-2ba02670603c	\N	Attachment	bd88ab9c-2738-4d43-8286-6327845a2487	Uploaded	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"version": 1, "fileName": "vendor-due-diligence.pdf"}	\N	2026-09-25 06:50:11.937225+00
18e4c58f-d0cd-4f66-b771-14e09c95444b	3976f8cd-9fce-4858-b550-2ba02670603c	\N	Attachment	268823cf-622d-4280-b349-f5d2d6534dc7	Uploaded	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"version": 1, "fileName": "product-spec.docx"}	\N	2026-09-25 06:50:12.283236+00
3a14dbe7-b2fa-42c1-96fe-b3b6534da628	3976f8cd-9fce-4858-b550-2ba02670603c	\N	Attachment	f615d44c-1079-495e-93d7-b65e2178c38f	Uploaded	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"version": 1, "fileName": "control-matrix.xlsx"}	\N	2026-09-25 06:50:12.611676+00
722ae01d-e6b2-40f0-9f1f-d79348623120	b5e1065a-a458-4f71-a672-0d3a516a4578	\N	ChangeRequest	b5e1065a-a458-4f71-a672-0d3a516a4578	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609250649] bad uploads", "status": "Submitted", "changeType": "Vendor"}	\N	2026-09-25 06:50:14.895356+00
67440619-85d6-4284-be64-73d8451e3ae2	b5e1065a-a458-4f71-a672-0d3a516a4578	\N	Attachment	f56475d8-fd35-4453-b1bb-657f94479756	Uploaded	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"version": 1, "fileName": "malicious.exe"}	\N	2026-09-25 06:50:15.750002+00
25be1b81-d233-4f2b-b6fb-f53f99a9b724	c73e1706-d774-4fb7-9a86-95f260c31f2b	\N	ChangeRequest	c73e1706-d774-4fb7-9a86-95f260c31f2b	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609250649] clarification", "status": "Submitted", "changeType": "Geography"}	\N	2026-09-25 06:50:17.709215+00
ecee1ea2-b35c-4822-8a79-a6a89a795854	c73e1706-d774-4fb7-9a86-95f260c31f2b	\N	Clarification	a9f95b5a-9001-4baa-b82e-6d0b9be40ad3	Requested	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"question": "Which target countries exactly?"}	\N	2026-09-25 06:50:18.019016+00
c2c1c597-4347-4528-b0ea-492ea672a560	a0c484e3-fdc0-4275-bbee-51fec3c0f04d	\N	ChangeRequest	a0c484e3-fdc0-4275-bbee-51fec3c0f04d	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609250649] snapshot linked", "status": "Submitted", "changeType": "Product"}	\N	2026-09-25 06:50:19.236347+00
6b70b720-9a33-4a0e-8290-b907e5d58af4	a0c484e3-fdc0-4275-bbee-51fec3c0f04d	\N	ExternalSnapshot	a0c484e3-fdc0-4275-bbee-51fec3c0f04d	Ingested	\N	system	\N	{"hasVendor": false, "hasProduct": true, "hasCustomer": false}	\N	2026-09-25 06:50:19.302948+00
2610ee0d-4ffb-4286-817b-1c7af754dc78	40affe4d-9ba8-48a6-b354-d60668956ac6	\N	ChangeRequest	40affe4d-9ba8-48a6-b354-d60668956ac6	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609250649] snapshot none", "status": "Submitted", "changeType": "Process"}	\N	2026-09-25 06:50:19.597754+00
614d6e6d-8f13-4876-8ab3-c8abce4e588e	9fd8d7bc-d6d7-4e7a-912f-f375ddd98a6c	\N	ChangeRequest	9fd8d7bc-d6d7-4e7a-912f-f375ddd98a6c	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E probe] versioning", "status": "Submitted", "changeType": "Vendor"}	\N	2026-09-25 06:50:40.560319+00
ac4513aa-33de-417e-b322-dfd450b5cdd8	9fd8d7bc-d6d7-4e7a-912f-f375ddd98a6c	\N	Attachment	c78afb44-6472-4fb8-8cae-e5ad15f7f27f	Uploaded	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"version": 1, "fileName": "a.pdf"}	\N	2026-09-25 06:50:41.634989+00
032eea20-cf19-423b-9d2c-c4dc6d111232	9fd8d7bc-d6d7-4e7a-912f-f375ddd98a6c	\N	Attachment	3ee6c57f-3dac-43a8-b682-850e1711ce46	Uploaded	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"version": 1, "fileName": "vendor-due-diligence.pdf"}	\N	2026-09-25 06:50:44.516777+00
7a010dd0-2a2e-4924-8294-520c71bc2455	89313b30-9064-4caa-8838-29e42ddc72f2	\N	ChangeRequest	89313b30-9064-4caa-8838-29e42ddc72f2	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609250653] API lifecycle - onboard settlement vendor", "status": "Submitted", "changeType": "Vendor"}	\N	2026-09-25 06:53:46.849586+00
c75ee47e-e242-4e56-ab5e-459693a0c86f	89313b30-9064-4caa-8838-29e42ddc72f2	\N	ExternalSnapshot	89313b30-9064-4caa-8838-29e42ddc72f2	Ingested	\N	system	\N	{"hasVendor": true, "hasProduct": false, "hasCustomer": false}	\N	2026-09-25 06:53:46.925689+00
36f7c608-ec34-4827-93e2-165f5c27e709	89313b30-9064-4caa-8838-29e42ddc72f2	\N	Attachment	7ccdf7d2-288f-4a80-833f-4720064f1d5f	Uploaded	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"version": 1, "fileName": "vendor-due-diligence.pdf"}	\N	2026-09-25 06:53:47.313765+00
c1733f87-6a80-4ac9-8faa-d574d5e75881	89313b30-9064-4caa-8838-29e42ddc72f2	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	Assessment	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	Finalized	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"finalizedBy": "4fa322d3-2245-44ef-b664-1a804442db23"}	\N	2026-09-25 06:53:49.633755+00
c149ff00-df1b-407c-965b-ccc165dd7357	89313b30-9064-4caa-8838-29e42ddc72f2	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	ChangeRequest	89313b30-9064-4caa-8838-29e42ddc72f2	Routed	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"status": "PendingCommittee"}	\N	2026-09-25 06:53:49.947963+00
ab58fdc4-6024-4745-aae2-1154a0b3b3a1	\N	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	CategoryMapping	a82905b6-ddfe-47ca-a728-9ee721cb1c14	AiProposed	\N	system/AI	\N	{"citation": "FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Customers", "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	\N	2026-09-25 06:53:54.517089+00
c8957a2e-2a12-4659-ab78-d87266f56b8a	\N	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	CategoryMapping	8b27f16c-085d-48b5-8cde-3c433ec983a3	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"isActive": true, "riskCategoryId": "22222222-2222-2222-2222-222222222223"}	Vendor is domiciled in Malta - geographic exposure	2026-09-25 06:53:56.719885+00
1c089a93-bdac-485a-9c62-ed184c740e92	\N	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	CategoryMapping	1609446d-6088-4bc5-8cb6-a93ee2724ff8	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"isActive": false, "riskCategoryId": "22222222-2222-2222-2222-222222222224"}	QA: removal test	2026-09-25 06:53:57.026033+00
5c9e21e2-79c1-4497-9d32-e815e9a93908	\N	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	CategoryMapping	1609446d-6088-4bc5-8cb6-a93ee2724ff8	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "1609446d-6088-4bc5-8cb6-a93ee2724ff8", "source": "AnalystAdded", "is_active": false, "created_at": "2026-09-25T06:53:57.026033+00:00", "ai_citation": null, "assessment_id": "709e7f0b-5cc4-45ff-ac85-e19c2a56eab6", "risk_category_id": "22222222-2222-2222-2222-222222222224", "created_by_user_id": "4fa322d3-2245-44ef-b664-1a804442db23"}	{"isActive": true, "riskCategoryId": "22222222-2222-2222-2222-222222222224"}	QA: restore - API channel is non-face-to-face	2026-09-25 06:53:57.323471+00
a08997e8-28b0-4f4a-a677-bcb3b4f043c7	\N	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	PolicyReliance	dfe6cf7b-3c52-455a-bb8a-3ac4cccef494	Decided	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"decision": "ReliedUpon", "policyChunkId": "e7a09ebd-9c1f-4779-8499-fa131c4a77c4"}	\N	2026-09-25 06:54:03.29178+00
69f3795e-8262-43ad-939f-693ad7b1d6e5	\N	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	PolicyReliance	dfe6cf7b-3c52-455a-bb8a-3ac4cccef494	Decided	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"decision": "ReliedUpon", "policyChunkId": "e7a09ebd-9c1f-4779-8499-fa131c4a77c4"}	\N	2026-09-25 06:54:03.612064+00
c9d4c0e3-5379-4a56-99d7-474b6e48628b	\N	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	PolicyReliance	dfe6cf7b-3c52-455a-bb8a-3ac4cccef494	Decided	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"decision": "ReliedUpon", "policyChunkId": "e7a09ebd-9c1f-4779-8499-fa131c4a77c4"}	\N	2026-09-25 06:54:03.907812+00
93053d94-e0a4-438e-a56d-e53118376876	\N	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	PolicyReliance	7a25a613-aeaa-4956-b361-914625c6ff96	Decided	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"decision": "NotRelevant", "policyChunkId": "af07f40f-b9fa-4614-891b-b0fcc9a8f54b"}	\N	2026-09-25 06:54:04.20961+00
77452cd2-3ff1-46dc-9eb8-1ff766b2a78f	89313b30-9064-4caa-8838-29e42ddc72f2	\N	ExtractedField	8a9bac73-2605-415d-9718-50cb9f3cfd56	AiExtracted	\N	system/AI	\N	{"value": "QuickPay Processing Ltd", "fieldKey": "vendor_name", "confidence": 1, "needsReview": false}	\N	2026-09-25 06:54:08.908696+00
56018512-c9d2-4876-a82f-b2a4e824b2dc	89313b30-9064-4caa-8838-29e42ddc72f2	\N	ExtractedField	c748243e-9efe-4bcb-bd3d-cab8c94b42c3	AiExtracted	\N	system/AI	\N	{"value": "Malta", "fieldKey": "vendor_jurisdiction", "confidence": 1, "needsReview": false}	\N	2026-09-25 06:54:08.94276+00
7a2b3462-4650-4e48-9d29-694f41c0d640	89313b30-9064-4caa-8838-29e42ddc72f2	\N	ExtractedField	b8c66dd3-ce46-432f-88c9-72bd11869b8f	AiExtracted	\N	system/AI	\N	{"value": "cardholder PII and settlement files", "fieldKey": "data_access_scope", "confidence": 1, "needsReview": false}	\N	2026-09-25 06:54:08.975603+00
29d899fc-551b-4481-84b4-d53fd53e9a2c	89313b30-9064-4caa-8838-29e42ddc72f2	\N	ExtractedField	4a3e6781-c5b4-4a79-88cd-82a698b68ad9	AiExtracted	\N	system/AI	\N	{"value": "retail cardholders, MSB merchants", "fieldKey": "customer_types_affected", "confidence": 1, "needsReview": false}	\N	2026-09-25 06:54:09.007583+00
eb85f03b-4357-418d-b744-08fdd0deab0f	89313b30-9064-4caa-8838-29e42ddc72f2	\N	ExtractedField	c93aa97d-143a-46b3-b643-4a8b255d93f6	AiExtracted	\N	system/AI	\N	{"value": "API, non-face-to-face", "fieldKey": "delivery_channel", "confidence": 1, "needsReview": false}	\N	2026-09-25 06:54:09.040168+00
2c3afb25-1517-4abd-86c4-12c6f027c4fd	89313b30-9064-4caa-8838-29e42ddc72f2	\N	ExtractedField	8a9bac73-2605-415d-9718-50cb9f3cfd56	Corrected	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "8a9bac73-2605-415d-9718-50cb9f3cfd56", "source": "AiExtracted", "field_key": "vendor_name", "confidence": 1.000, "updated_at": "2026-09-25T06:54:08.908696+00:00", "field_value": "QuickPay Processing Ltd", "needs_review": false, "attachment_id": "7ccdf7d2-288f-4a80-833f-4720064f1d5f", "source_excerpt": "Vendor name: QuickPay Processing Ltd", "change_request_id": "89313b30-9064-4caa-8838-29e42ddc72f2", "updated_by_user_id": null}	{"value": "QA value ", "fieldKey": "vendor_name"}	\N	2026-09-25 06:54:10.576856+00
d3d01a89-4df2-49fa-855c-ef31fa3dcd09	89313b30-9064-4caa-8838-29e42ddc72f2	\N	ExtractedField	8a9bac73-2605-415d-9718-50cb9f3cfd56	Corrected	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "8a9bac73-2605-415d-9718-50cb9f3cfd56", "source": "AnalystCorrected", "field_key": "vendor_name", "confidence": null, "updated_at": "2026-09-25T06:54:10.576856+00:00", "field_value": "QA value ", "needs_review": false, "attachment_id": "7ccdf7d2-288f-4a80-833f-4720064f1d5f", "source_excerpt": "Vendor name: QuickPay Processing Ltd", "change_request_id": "89313b30-9064-4caa-8838-29e42ddc72f2", "updated_by_user_id": "4fa322d3-2245-44ef-b664-1a804442db23"}	{"value": "QA corrected value", "fieldKey": "vendor_name"}	Contract section 4 states otherwise	2026-09-25 06:54:10.8808+00
f974cfb0-9f3c-48e7-ba90-48cc886984b5	\N	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	NarrativeSection	30aed139-f516-44c7-b390-dc43d50816dc	AiDrafted	\N	system/AI	\N	{"text": "The proposed business change involves onboarding a Malta-based vendor, QA, to serve as a card settlement processor with access to cardholder personally identifiable information (PII) and settlement files. This vendor will process transactions involving retail cardholders and money services business (MSB) merchants. Given that MSBs are recognized categories of customers that pose elevated money laundering risks, and considering the vendor operates internationally in Malta, the risk profile may be heightened. Furthermore, the delivery channel for the vendor's services will be via API, a non-face-to-face channel, which can further increase exposure to potential financial crime risks due to the reduced ability to perform direct verification.\\n\\nIn alignment with the FFIEC BSA/AML Manual guidance on Risks Associated with Money Laundering and Terrorist Financing related to Customers, customer due diligence must scale its scrutiny based on the risk profile of the customer or entity involved (Section: Risks Associated with Money Laundering and Terrorist Financing - Customers). Therefore, the vendor's jurisdiction, the access to sensitive data, and involvement with higher-risk customer types such as MSBs necessitate heightened due diligence and continual monitoring consistent with a risk-based customer due diligence program. This approach will help ensure that the bank appropriately manages elevated risks posed by complex relationships with this external processing entity.", "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	\N	2026-09-25 06:54:16.260008+00
2bd5bb34-262f-487e-9b0a-2bf9b56c8699	\N	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	NarrativeSection	4093f912-043c-4563-84ea-2579492247bd	AiDrafted	\N	system/AI	\N	{"text": "The proposed business change involves onboarding a vendor, QA corrected value, a Malta-based card settlement processor. This vendor will have access to sensitive cardholder personally identifiable information (PII) and settlement files. Given that Malta is the vendor's jurisdiction, the bank must evaluate the geographic risks associated with money laundering and terrorist financing in this location as outlined in the FFIEC BSA/AML Manual under Geographic Locations risks.\\\\n\\\\nAccess to cardholder PII and settlement data via an API in a non-face-to-face delivery channel inherently raises concerns about transaction monitoring and data security due to the increased risk profile of remote interactions. The impact extends across customer types, including retail cardholders and money services business (MSB) merchants, both of whom could be vulnerable to illicit activity facilitated through this vendor relationship.\\\\n\\\\nThe bank’s risk management should ensure enhanced due diligence and ongoing monitoring to address the potential exposure introduced through this geographic location, focusing on compliance with the guidance provided in the FFIEC BSA/AML Manual concerning geographic risks related to money laundering and terrorist financing.", "riskCategoryId": "22222222-2222-2222-2222-222222222223"}	\N	2026-09-25 06:54:19.673428+00
22de4d50-9ebc-48fd-ab34-e09bf7d6e446	\N	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	NarrativeSection	e923f480-f683-4919-94ff-562dd2b26cd6	AiDrafted	\N	system/AI	\N	{"text": "The proposed business change involves onboarding a Malta-based vendor named QA as a card settlement processor, granting the vendor access to cardholder personally identifiable information (PII) and settlement files. This onboarding introduces a non-face-to-face delivery channel through an API interface, which inherently increases the complexity and risks associated with money laundering and terrorist financing activities, as noted in the FFIEC BSA/AML Manual under \\"Risks Associated with Money Laundering and Terrorist Financing: Products and Services (Delivery Channels)\\". The lack of direct, in-person interaction in this API-based delivery channel underscores the importance of robust risk controls and monitoring mechanisms to mitigate the elevated risks.", "riskCategoryId": "22222222-2222-2222-2222-222222222224"}	\N	2026-09-25 06:54:22.472949+00
669d3e2a-2ea9-4d3f-9bcd-f01d7b1c94e0	\N	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	NarrativeSection	30aed139-f516-44c7-b390-dc43d50816dc	AiDrafted	\N	system/AI	{"id": "30aed139-f516-44c7-b390-dc43d50816dc", "status": "AiDrafted", "updated_at": "2026-09-25T06:54:16.260008+00:00", "assessment_id": "709e7f0b-5cc4-45ff-ac85-e19c2a56eab6", "narrative_text": "The proposed business change involves onboarding a Malta-based vendor, QA, to serve as a card settlement processor with access to cardholder personally identifiable information (PII) and settlement files. This vendor will process transactions involving retail cardholders and money services business (MSB) merchants. Given that MSBs are recognized categories of customers that pose elevated money laundering risks, and considering the vendor operates internationally in Malta, the risk profile may be heightened. Furthermore, the delivery channel for the vendor's services will be via API, a non-face-to-face channel, which can further increase exposure to potential financial crime risks due to the reduced ability to perform direct verification.\\n\\nIn alignment with the FFIEC BSA/AML Manual guidance on Risks Associated with Money Laundering and Terrorist Financing related to Customers, customer due diligence must scale its scrutiny based on the risk profile of the customer or entity involved (Section: Risks Associated with Money Laundering and Terrorist Financing - Customers). Therefore, the vendor's jurisdiction, the access to sensitive data, and involvement with higher-risk customer types such as MSBs necessitate heightened due diligence and continual monitoring consistent with a risk-based customer due diligence program. This approach will help ensure that the bank appropriately manages elevated risks posed by complex relationships with this external processing entity.", "risk_category_id": "22222222-2222-2222-2222-222222222222", "updated_by_user_id": null, "unsupported_claim_flags": []}	{"text": "The proposed business change to onboard the Malta-based vendor QA corrected value as a card settlement processor introduces specific considerations under the Customers & Entities risk category. Given the vendor's access to sensitive cardholder PII and settlement files via a non-face-to-face API delivery channel, heightened attention to the risk profile is warranted. According to the FFIEC BSA/AML Manual, certain customer types such as money services businesses and non-resident entities may represent elevated money laundering risk and thus require a risk-based customer due diligence approach (Risks Associated with Money Laundering and Terrorist Financing - Customers). Since the affected customer base includes retail cardholders and MSB merchants, the scrutiny measures should appropriately scale to these risks, factoring in the Malta jurisdiction, which may carry its own regulatory considerations.", "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	\N	2026-09-25 06:54:27.658103+00
0373c847-0a68-493c-b23b-1c462ede3ad6	\N	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	NarrativeSection	30aed139-f516-44c7-b390-dc43d50816dc	AnalystEdited	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "30aed139-f516-44c7-b390-dc43d50816dc", "status": "AiDrafted", "updated_at": "2026-09-25T06:54:27.658103+00:00", "assessment_id": "709e7f0b-5cc4-45ff-ac85-e19c2a56eab6", "narrative_text": "The proposed business change to onboard the Malta-based vendor QA corrected value as a card settlement processor introduces specific considerations under the Customers & Entities risk category. Given the vendor's access to sensitive cardholder PII and settlement files via a non-face-to-face API delivery channel, heightened attention to the risk profile is warranted. According to the FFIEC BSA/AML Manual, certain customer types such as money services businesses and non-resident entities may represent elevated money laundering risk and thus require a risk-based customer due diligence approach (Risks Associated with Money Laundering and Terrorist Financing - Customers). Since the affected customer base includes retail cardholders and MSB merchants, the scrutiny measures should appropriately scale to these risks, factoring in the Malta jurisdiction, which may carry its own regulatory considerations.", "risk_category_id": "22222222-2222-2222-2222-222222222222", "updated_by_user_id": null, "unsupported_claim_flags": []}	{"text": "QA analyst narrative: vendor in Malta processes cardholder PII via API; enhanced due diligence and contractual audit rights required.", "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	Tightened wording and added EDD requirement	2026-09-25 06:54:29.661292+00
2ef39125-1597-44a4-9a68-242aeb0f0531	\N	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	NarrativeSection	4093f912-043c-4563-84ea-2579492247bd	AnalystReviewed	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"status": "AnalystReviewed", "riskCategoryId": "22222222-2222-2222-2222-222222222223"}	\N	2026-09-25 06:54:29.94835+00
e89334f1-3a0a-4737-885e-6f4947afe0d9	\N	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	NarrativeSection	e923f480-f683-4919-94ff-562dd2b26cd6	AnalystReviewed	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"status": "AnalystReviewed", "riskCategoryId": "22222222-2222-2222-2222-222222222224"}	\N	2026-09-25 06:54:30.229255+00
cc717a88-274e-4d7f-92e9-6073430f6989	\N	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	RiskScore	bd155f09-5e5a-46cb-85c6-a44b5f0e2ae6	Calculated	\N	system/AI	\N	{"inherent": 4, "residual": 3.3200, "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	\N	2026-09-25 06:54:31.353231+00
5d2a29fc-8bba-46c5-b057-e8eb0017d22b	\N	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	RiskScore	40f4db9e-eeeb-4d77-8c2d-a376dc30e764	Calculated	\N	system/AI	\N	{"inherent": 1, "residual": 0.150, "riskCategoryId": "22222222-2222-2222-2222-222222222223"}	\N	2026-09-25 06:54:31.678708+00
2ef794a3-f68e-429a-b9df-ee360d38c7f0	\N	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	RiskScore	fc27ab2b-3596-45a8-ba46-3cac9bebe5af	Calculated	\N	system/AI	\N	{"inherent": 3, "residual": 2.5750, "riskCategoryId": "22222222-2222-2222-2222-222222222224"}	\N	2026-09-25 06:54:32.014593+00
bc6b4596-0a37-4630-9c9f-e7136baf8a11	\N	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	RiskScore	bd155f09-5e5a-46cb-85c6-a44b5f0e2ae6	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "bd155f09-5e5a-46cb-85c6-a44b5f0e2ae6", "scored_by": "System", "created_at": "2026-09-25T06:54:31.353231+00:00", "is_override": false, "assessment_id": "709e7f0b-5cc4-45ff-ac85-e19c2a56eab6", "inherent_rating": 4.00, "override_reason": null, "residual_rating": 3.32, "risk_category_id": "22222222-2222-2222-2222-222222222222", "created_by_user_id": null, "control_ids_credited": [], "control_effectiveness": 0.800, "mitigation_factor_applied": 0.850}	{"residual": 2.5, "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	Vendor has had two prior regulatory findings	2026-09-25 06:54:36.813996+00
b15b5f48-9375-4e66-9979-82df39c94e25	89313b30-9064-4caa-8838-29e42ddc72f2	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	CommitteeVote	d4ee845c-3eaf-4d55-9a58-f55746395b01	Voted	083ecfe5-aa01-4703-9168-762f0065078f	human	\N	{"vote": "Approve", "rationale": null, "conditionsText": null}	\N	2026-09-25 06:54:40.328689+00
ac57db89-29a5-47df-bf69-c793161bd46b	\N	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	NarrativeSection	30aed139-f516-44c7-b390-dc43d50816dc	AnalystEdited	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "30aed139-f516-44c7-b390-dc43d50816dc", "status": "AnalystEdited", "updated_at": "2026-09-25T06:54:29.661292+00:00", "assessment_id": "709e7f0b-5cc4-45ff-ac85-e19c2a56eab6", "narrative_text": "QA analyst narrative: vendor in Malta processes cardholder PII via API; enhanced due diligence and contractual audit rights required.", "risk_category_id": "22222222-2222-2222-2222-222222222222", "updated_by_user_id": "4fa322d3-2245-44ef-b664-1a804442db23", "unsupported_claim_flags": []}	{"text": "post-finalize tamper", "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	QA lock test	2026-09-25 06:54:44.059194+00
b69f0048-0874-4366-aeb9-9e7c3827d702	\N	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	RiskScore	bd155f09-5e5a-46cb-85c6-a44b5f0e2ae6	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "bd155f09-5e5a-46cb-85c6-a44b5f0e2ae6", "scored_by": "System", "created_at": "2026-09-25T06:54:31.353231+00:00", "is_override": true, "assessment_id": "709e7f0b-5cc4-45ff-ac85-e19c2a56eab6", "inherent_rating": 4.00, "override_reason": "Vendor has had two prior regulatory findings", "residual_rating": 2.50, "risk_category_id": "22222222-2222-2222-2222-222222222222", "created_by_user_id": null, "control_ids_credited": [], "control_effectiveness": 0.800, "mitigation_factor_applied": 0.850}	{"residual": 0.5, "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	QA lock test	2026-09-25 06:54:44.357214+00
7a8900e7-f42d-47da-8713-68f7038b137a	\N	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	CategoryMapping	da627fc8-b5f9-4374-bbe6-a87d1236cb44	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"isActive": true, "riskCategoryId": "22222222-2222-2222-2222-222222222221"}	QA lock test	2026-09-25 06:54:44.663647+00
fcabb95d-80d4-476c-9042-ce2ff6f55df7	89313b30-9064-4caa-8838-29e42ddc72f2	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	CommitteeVote	d4ee845c-3eaf-4d55-9a58-f55746395b01	Voted	083ecfe5-aa01-4703-9168-762f0065078f	human	\N	{"vote": "ApproveWithConditions", "rationale": null, "conditionsText": ""}	\N	2026-09-25 06:54:47.018183+00
b5a86012-8f7b-4777-ba74-f5e0207b55ed	89313b30-9064-4caa-8838-29e42ddc72f2	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	CommitteeVote	d4ee845c-3eaf-4d55-9a58-f55746395b01	Voted	083ecfe5-aa01-4703-9168-762f0065078f	human	\N	{"vote": "Defer", "rationale": "   ", "conditionsText": null}	\N	2026-09-25 06:54:47.898642+00
865fcf5b-d7f1-442a-965c-7eeef1445a22	89313b30-9064-4caa-8838-29e42ddc72f2	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	CommitteeVote	7563078a-c4fb-4822-8984-dad840ee1ae9	Voted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"vote": "Approve", "rationale": null, "conditionsText": null}	\N	2026-09-25 06:54:48.757173+00
4208cf37-eed4-4bb5-9299-b2c541785397	89313b30-9064-4caa-8838-29e42ddc72f2	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	CommitteeDecision	4f605330-0194-4b2f-9f16-8cafcc6975f6	Decisioned	\N	system/AI	\N	{"resolution": "Deferred", "conditionsText": null}	\N	2026-09-25 06:54:48.882644+00
7893f4f9-87c3-45b5-839f-7e4b28a5f0c3	89313b30-9064-4caa-8838-29e42ddc72f2	\N	MockSystemsFeedback	89313b30-9064-4caa-8838-29e42ddc72f2	Pushed	\N	system	\N	{"goLive": false, "resolution": "Deferred", "ratingSummary": "Deferred - pending further committee review"}	\N	2026-09-25 06:54:49.431584+00
81eecd1b-6de9-4f96-86ab-ffeb131830db	298d4e01-a257-407a-9f27-04b96c02ff54	\N	ChangeRequest	298d4e01-a257-407a-9f27-04b96c02ff54	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609250658] API lifecycle - onboard settlement vendor", "status": "Submitted", "changeType": "Vendor"}	\N	2026-09-25 06:58:38.557773+00
ecae9a89-c676-40d5-9801-4c100589cf21	298d4e01-a257-407a-9f27-04b96c02ff54	\N	ExternalSnapshot	298d4e01-a257-407a-9f27-04b96c02ff54	Ingested	\N	system	\N	{"hasVendor": true, "hasProduct": false, "hasCustomer": false}	\N	2026-09-25 06:58:38.637477+00
7df8667f-03b7-4b94-abde-a5c33a45cb8d	298d4e01-a257-407a-9f27-04b96c02ff54	\N	Attachment	b95d8cc7-a14f-4176-b87a-56d9a8072f03	Uploaded	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"version": 1, "fileName": "vendor-due-diligence.pdf"}	\N	2026-09-25 06:58:39.046798+00
1836a156-30dd-4d0c-acd3-1c17b198414f	83f2c245-439e-4b8a-8206-ee1bda436d80	\N	ChangeRequest	83f2c245-439e-4b8a-8206-ee1bda436d80	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609250658] API probe - empty assessment", "status": "Submitted", "changeType": "Feature"}	\N	2026-09-25 06:58:40.934675+00
7552db3e-e4aa-417b-8d2c-69638cc86a4b	83f2c245-439e-4b8a-8206-ee1bda436d80	12f0ad4a-87e9-494c-924e-20be52169763	Assessment	12f0ad4a-87e9-494c-924e-20be52169763	Finalized	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"finalizedBy": "4fa322d3-2245-44ef-b664-1a804442db23"}	\N	2026-09-25 06:58:42.052363+00
2aa4e3ae-95f0-4224-94f1-e3c47a33257a	83f2c245-439e-4b8a-8206-ee1bda436d80	12f0ad4a-87e9-494c-924e-20be52169763	ChangeRequest	83f2c245-439e-4b8a-8206-ee1bda436d80	Routed	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"status": "PendingCommittee"}	\N	2026-09-25 06:58:42.362451+00
1ed5e8f7-1446-46f3-8216-2d8bf06feed2	\N	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	CategoryMapping	d6a5a12f-d5ee-485e-9778-e6d4fc2f95ff	AiProposed	\N	system/AI	\N	{"citation": "FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Customers", "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	\N	2026-09-25 06:58:45.996506+00
6e19b36e-88f9-48e9-b4f9-e8df4a38ee1d	\N	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	CategoryMapping	a53f2ebc-05f5-4585-91ca-d25a4bddd0d0	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"isActive": true, "riskCategoryId": "22222222-2222-2222-2222-222222222223"}	Vendor is domiciled in Malta - geographic exposure	2026-09-25 06:58:49.247879+00
ec9ebe85-2da7-4de1-9f7f-86b3631c99b9	\N	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	CategoryMapping	36f8a528-bb96-4c8d-8e1f-cbe00dad8f65	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"isActive": false, "riskCategoryId": "22222222-2222-2222-2222-222222222224"}	QA: removal test	2026-09-25 06:58:49.577231+00
2e590a47-ba8c-42b9-9121-ec18c046699b	\N	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	CategoryMapping	36f8a528-bb96-4c8d-8e1f-cbe00dad8f65	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "36f8a528-bb96-4c8d-8e1f-cbe00dad8f65", "source": "AnalystAdded", "is_active": false, "created_at": "2026-09-25T06:58:49.577231+00:00", "ai_citation": null, "assessment_id": "b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a", "risk_category_id": "22222222-2222-2222-2222-222222222224", "created_by_user_id": "4fa322d3-2245-44ef-b664-1a804442db23"}	{"isActive": true, "riskCategoryId": "22222222-2222-2222-2222-222222222224"}	QA: restore - API channel is non-face-to-face	2026-09-25 06:58:49.882503+00
89400c5f-8433-4921-8e09-52bd005d91d8	\N	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	PolicyReliance	d4d2b7eb-35a9-41d7-9246-11a9679e421e	Decided	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"decision": "ReliedUpon", "policyChunkId": "3f171e93-f2ca-40a4-af6a-18ede9021c9b"}	\N	2026-09-25 06:58:55.039924+00
558564ed-c462-4c56-a63c-85f220892979	\N	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	PolicyReliance	4baaf28d-33f5-470d-9984-1b647d4806a1	Decided	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"decision": "ReliedUpon", "policyChunkId": "539e307e-5d18-454b-a33c-fbcf3ff8c407"}	\N	2026-09-25 06:58:55.32633+00
55ea0f27-841c-4286-96c9-f133d7342595	\N	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	PolicyReliance	8468f45e-76f4-46c5-b094-1634ff2f594e	Decided	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"decision": "ReliedUpon", "policyChunkId": "8fc9b915-62af-410e-af73-373e51aac522"}	\N	2026-09-25 06:58:55.614744+00
103180e7-6293-42c6-a19e-6ba3417aa4fe	\N	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	PolicyReliance	a27f811d-1d1d-4b0d-ba10-eec409ae9fba	Decided	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"decision": "NotRelevant", "policyChunkId": "af07f40f-b9fa-4614-891b-b0fcc9a8f54b"}	\N	2026-09-25 06:58:55.904231+00
d8b394df-5823-4a23-9427-216adfc67cc3	\N	12f0ad4a-87e9-494c-924e-20be52169763	PolicyReliance	4700c463-24f8-4619-9951-ba294141373a	Decided	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"decision": "ReliedUpon", "policyChunkId": "3f171e93-f2ca-40a4-af6a-18ede9021c9b"}	\N	2026-09-25 06:58:59.090026+00
04e0a2da-5212-47bf-b0e6-d15501370e59	\N	12f0ad4a-87e9-494c-924e-20be52169763	PolicyReliance	4700c463-24f8-4619-9951-ba294141373a	Decided	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"decision": "ReliedUpon", "policyChunkId": "3f171e93-f2ca-40a4-af6a-18ede9021c9b"}	\N	2026-09-25 06:58:59.399046+00
01ec8806-5959-4c9d-bcb2-3f75a2b5c16b	298d4e01-a257-407a-9f27-04b96c02ff54	\N	ExtractedField	3bf273f8-0362-4116-a5da-abf04f732ac6	AiExtracted	\N	system/AI	\N	{"value": "QuickPay Processing Ltd", "fieldKey": "vendor_name", "confidence": 1, "needsReview": false}	\N	2026-09-25 06:59:04.099116+00
8aab6fa2-5b8f-4cc6-b204-2a654f01a7f2	298d4e01-a257-407a-9f27-04b96c02ff54	\N	ExtractedField	ffe73d55-3ab5-451d-b66d-8e6e0d8acfbc	AiExtracted	\N	system/AI	\N	{"value": "Malta", "fieldKey": "vendor_jurisdiction", "confidence": 1, "needsReview": false}	\N	2026-09-25 06:59:04.132252+00
55e3500f-138c-44a8-90b1-1a95d18f90b6	298d4e01-a257-407a-9f27-04b96c02ff54	\N	ExtractedField	6899e3d3-b69b-4c61-8c6c-a63acdc86510	AiExtracted	\N	system/AI	\N	{"value": "cardholder PII and settlement files", "fieldKey": "data_access_scope", "confidence": 1, "needsReview": false}	\N	2026-09-25 06:59:04.165023+00
b41d9280-9e2f-4213-8479-9fead239d8f2	298d4e01-a257-407a-9f27-04b96c02ff54	\N	ExtractedField	cde677eb-70dd-4cde-a479-fbeee148b1e2	AiExtracted	\N	system/AI	\N	{"value": "retail cardholders, MSB merchants", "fieldKey": "customer_types_affected", "confidence": 1, "needsReview": false}	\N	2026-09-25 06:59:04.197314+00
78d00712-0ca2-4dc4-a87b-6496235df949	298d4e01-a257-407a-9f27-04b96c02ff54	\N	ExtractedField	317f2c4f-28ef-4d27-81bf-4c893e91637a	AiExtracted	\N	system/AI	\N	{"value": "API, non-face-to-face", "fieldKey": "delivery_channel", "confidence": 1, "needsReview": false}	\N	2026-09-25 06:59:04.231569+00
64729afa-4d61-47d4-a9d7-f48b5f5310d2	298d4e01-a257-407a-9f27-04b96c02ff54	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	CommitteeVote	ffb7083e-c452-4dfe-ab12-314e38bc113a	Voted	fa142c1c-58cc-4666-b135-7768a2ab33f0	human	\N	{"vote": "Approve", "rationale": null, "conditionsText": null}	\N	2026-09-25 06:59:50.711113+00
1bda7d02-ef61-404c-9710-cc6c5dcb51ab	298d4e01-a257-407a-9f27-04b96c02ff54	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	CommitteeDecision	61cea176-52dd-4866-848d-d57137b4e83f	Decisioned	\N	system/AI	\N	{"resolution": "ApprovedWithConditions", "conditionsText": "Jordan Blake: Annual on-site audit of the vendor; PII encrypted at rest"}	\N	2026-09-25 06:59:50.836323+00
ee563fb1-1dec-4b4c-a724-4a78cc83b4c8	298d4e01-a257-407a-9f27-04b96c02ff54	\N	ExtractedField	3bf273f8-0362-4116-a5da-abf04f732ac6	Corrected	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "3bf273f8-0362-4116-a5da-abf04f732ac6", "source": "AiExtracted", "field_key": "vendor_name", "confidence": 1.000, "updated_at": "2026-09-25T06:59:04.099116+00:00", "field_value": "QuickPay Processing Ltd", "needs_review": false, "attachment_id": "b95d8cc7-a14f-4176-b87a-56d9a8072f03", "source_excerpt": "Vendor name: QuickPay Processing Ltd", "change_request_id": "298d4e01-a257-407a-9f27-04b96c02ff54", "updated_by_user_id": null}	{"value": "QA value ", "fieldKey": "vendor_name"}	\N	2026-09-25 06:59:05.660985+00
801e5605-041b-4da6-8cf1-2d1443a9d7ed	298d4e01-a257-407a-9f27-04b96c02ff54	\N	ExtractedField	3bf273f8-0362-4116-a5da-abf04f732ac6	Corrected	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "3bf273f8-0362-4116-a5da-abf04f732ac6", "source": "AnalystCorrected", "field_key": "vendor_name", "confidence": null, "updated_at": "2026-09-25T06:59:05.660985+00:00", "field_value": "QA value ", "needs_review": false, "attachment_id": "b95d8cc7-a14f-4176-b87a-56d9a8072f03", "source_excerpt": "Vendor name: QuickPay Processing Ltd", "change_request_id": "298d4e01-a257-407a-9f27-04b96c02ff54", "updated_by_user_id": "4fa322d3-2245-44ef-b664-1a804442db23"}	{"value": "QA corrected value", "fieldKey": "vendor_name"}	Contract section 4 states otherwise	2026-09-25 06:59:05.944154+00
978d6933-ad69-47f9-80ca-07d47ef28573	\N	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	NarrativeSection	f43a13f5-a778-4467-bc61-381babc6c557	AiDrafted	\N	system/AI	\N	{"text": "The proposed vendor onboarding involves a Malta-based card settlement processor, QA corrected value, which will have access to cardholder personally identifiable information (PII) and settlement files. This access implicates the bank's responsibility to appropriately manage the risks associated with money laundering and terrorist financing, especially given the non-face-to-face delivery channel via API. As noted in the supervisory guidance, products and services that feature limited face-to-face contact and involve rapid movement of funds, such as electronic funds transfers, are inherently vulnerable to abuse (Risks Associated with Money Laundering and Terrorist Financing - Products and Services). The affected customer types include retail cardholders and money services business (MSB) merchants, both of which require careful risk assessment due to their susceptibility to illicit activity.", "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	\N	2026-09-25 06:59:09.455248+00
d100b541-24ec-46da-b735-cf0a21118ee0	\N	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	NarrativeSection	f1fa018c-1349-40b0-8ff4-ee2d04358709	AiDrafted	\N	system/AI	\N	{"text": "The proposed onboarding of the Malta-based vendor, QA corrected value, introduces a new geographic risk factor associated with access to cardholder PII and settlement files. As the vendor operates in Malta, the bank must consider the inherent risks tied to geographic jurisdictions, in line with the FFIEC BSA/AML Manual guidance on Risks Associated with Money Laundering and Terrorist Financing: Geographic Locations. The use of a non-face-to-face delivery channel via API further elevates these risks by reducing the bank's ability to directly verify customer identity and intent, as specified in the policy section on Delivery Channels. This lack of face-to-face interaction requires enhanced due diligence and risk assessment measures to mitigate potential exploitation by illicit actors.\\n\\nMoreover, the affected customer types—including retail cardholders and MSB merchants—reflect a diverse set of clients, whose varying risk profiles must be factored comprehensively. Because the third-party vendor gains access to sensitive data through API channels, the bank should carefully evaluate its onboarding protocols, ensuring the vendor meets stringent data protection and AML compliance standards specific to the Malta jurisdiction. This is essential to manage risks tied to cross-border data flows and potential regulatory divergences in geographic risk contexts.", "riskCategoryId": "22222222-2222-2222-2222-222222222223"}	\N	2026-09-25 06:59:12.870292+00
d02234d2-c6f3-4093-a54f-8e234e5ca9db	\N	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	NarrativeSection	f2f9f73f-1bc1-452f-9c7f-39bdf40e0882	AiDrafted	\N	system/AI	\N	{"text": "The introduction of the Malta-based vendor 'QA corrected value' as a settlement processor providing access to cardholder PII and settlement files represents a notable change in the bank's delivery channels. Given the non-face-to-face API integration, this channel inherently increases exposure to risks associated with electronic access to sensitive customer information, particularly for retail cardholders and MSB merchants, as outlined in the FFIEC BSA/AML Manual regarding Delivery Channels risk (Risks Associated with Money Laundering and Terrorist Financing: Products and Services (Delivery Channels)). The reliance on an overseas vendor in Malta, a foreign jurisdiction, necessitates enhanced due diligence to ensure that the vendor's AML controls are robust and capable of mitigating risks tied to the vendor's own customer base (Correspondent Banking section).", "riskCategoryId": "22222222-2222-2222-2222-222222222224"}	\N	2026-09-25 06:59:15.515662+00
2c864c78-b1c5-4158-b69e-e84cd907e2ca	\N	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	NarrativeSection	f43a13f5-a778-4467-bc61-381babc6c557	AiDrafted	\N	system/AI	{"id": "f43a13f5-a778-4467-bc61-381babc6c557", "status": "AiDrafted", "updated_at": "2026-09-25T06:59:09.455248+00:00", "assessment_id": "b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a", "narrative_text": "The proposed vendor onboarding involves a Malta-based card settlement processor, QA corrected value, which will have access to cardholder personally identifiable information (PII) and settlement files. This access implicates the bank's responsibility to appropriately manage the risks associated with money laundering and terrorist financing, especially given the non-face-to-face delivery channel via API. As noted in the supervisory guidance, products and services that feature limited face-to-face contact and involve rapid movement of funds, such as electronic funds transfers, are inherently vulnerable to abuse (Risks Associated with Money Laundering and Terrorist Financing - Products and Services). The affected customer types include retail cardholders and money services business (MSB) merchants, both of which require careful risk assessment due to their susceptibility to illicit activity.", "risk_category_id": "22222222-2222-2222-2222-222222222222", "updated_by_user_id": null, "unsupported_claim_flags": []}	{"text": "The onboarding of the Malta-based vendor \\"QA corrected value\\" introduces heightened risks in the Customers & Entities category, given their access to sensitive cardholder PII and settlement files. As noted in the supervisory citation (FFIEC BSA/AML Manual), products involving rapid fund movement and limited face-to-face contact, such as electronic funds transfers via API channels, are inherently susceptible to money laundering risks. The vendor's non-face-to-face delivery channel further increases these vulnerabilities. Given the affected customer types include retail cardholders and MSB merchants, careful evaluation and mitigation of potential risks associated with the Malta jurisdiction and the scope of data access are essential to ensure compliance and risk management effectiveness as specified in the policy excerpt on products and services risks.", "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	\N	2026-09-25 06:59:21.46797+00
25e9e255-7932-4927-aa78-8458683b1937	298d4e01-a257-407a-9f27-04b96c02ff54	\N	MockSystemsFeedback	298d4e01-a257-407a-9f27-04b96c02ff54	Pushed	\N	system	\N	{"goLive": true, "resolution": "ApprovedWithConditions", "ratingSummary": "Approved with conditions: Jordan Blake: Annual on-site audit of the vendor; PII encrypted at rest"}	\N	2026-09-25 06:59:51.326978+00
3cc31ff6-d0a6-4549-8550-00a103f3e358	aff5b2e9-5ae7-4adf-8bf8-23de8bdca397	\N	ChangeRequest	aff5b2e9-5ae7-4adf-8bf8-23de8bdca397	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609250702] API probe - config versioning", "status": "Submitted", "changeType": "CustomerSegment"}	\N	2026-09-25 07:02:20.810607+00
2866b50b-40e3-4a08-9cf6-e90a49344660	\N	\N	ScoringConfig	dc972259-9776-40dd-8fe9-c65b6876723d	ConfigChanged	374a3158-6dfa-41f2-9a4d-3d1091dffacf	human	\N	{"riskCategoryId": "22222222-2222-2222-2222-222222222222", "maxMitigationFactor": 0.8}	QA: in-flight isolation test (restored immediately)	2026-09-25 07:02:21.444592+00
c883d648-29b3-4190-88e3-3c355c16126e	\N	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	NarrativeSection	f43a13f5-a778-4467-bc61-381babc6c557	AnalystEdited	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "f43a13f5-a778-4467-bc61-381babc6c557", "status": "AiDrafted", "updated_at": "2026-09-25T06:59:21.46797+00:00", "assessment_id": "b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a", "narrative_text": "The onboarding of the Malta-based vendor \\"QA corrected value\\" introduces heightened risks in the Customers & Entities category, given their access to sensitive cardholder PII and settlement files. As noted in the supervisory citation (FFIEC BSA/AML Manual), products involving rapid fund movement and limited face-to-face contact, such as electronic funds transfers via API channels, are inherently susceptible to money laundering risks. The vendor's non-face-to-face delivery channel further increases these vulnerabilities. Given the affected customer types include retail cardholders and MSB merchants, careful evaluation and mitigation of potential risks associated with the Malta jurisdiction and the scope of data access are essential to ensure compliance and risk management effectiveness as specified in the policy excerpt on products and services risks.", "risk_category_id": "22222222-2222-2222-2222-222222222222", "updated_by_user_id": null, "unsupported_claim_flags": []}	{"text": "QA analyst narrative: vendor in Malta processes cardholder PII via API; enhanced due diligence and contractual audit rights required.", "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	Tightened wording and added EDD requirement	2026-09-25 06:59:23.520209+00
08418af2-4252-44bb-9ef4-bf650880ea89	\N	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	NarrativeSection	f1fa018c-1349-40b0-8ff4-ee2d04358709	AnalystReviewed	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"status": "AnalystReviewed", "riskCategoryId": "22222222-2222-2222-2222-222222222223"}	\N	2026-09-25 06:59:23.789242+00
18f43689-1c75-4a6d-af7b-6f5abb98acde	\N	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	NarrativeSection	f2f9f73f-1bc1-452f-9c7f-39bdf40e0882	AnalystReviewed	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"status": "AnalystReviewed", "riskCategoryId": "22222222-2222-2222-2222-222222222224"}	\N	2026-09-25 06:59:24.062928+00
1f4c7d3a-4629-42e4-9e69-dc3e32ae2960	\N	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	RiskScore	c3971a0f-a1bd-41ab-b492-4837be759859	Calculated	\N	system/AI	\N	{"inherent": 4, "residual": 3.3200, "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	\N	2026-09-25 06:59:25.180503+00
e9b96e4c-ccf8-47be-ad72-7fb17e4f89f3	\N	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	RiskScore	8bef85f3-900b-4b73-b72d-d0142ec855f0	Calculated	\N	system/AI	\N	{"inherent": 1, "residual": 0.150, "riskCategoryId": "22222222-2222-2222-2222-222222222223"}	\N	2026-09-25 06:59:25.506723+00
e2d669ea-5717-4cfd-be19-721def8800e7	\N	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	RiskScore	dec88b7a-7ddc-4f30-ae24-a0bef4224a17	Calculated	\N	system/AI	\N	{"inherent": 3, "residual": 2.5750, "riskCategoryId": "22222222-2222-2222-2222-222222222224"}	\N	2026-09-25 06:59:25.837855+00
8dc0d648-0da3-4869-924b-97dcf6faa35f	\N	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	RiskScore	c3971a0f-a1bd-41ab-b492-4837be759859	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "c3971a0f-a1bd-41ab-b492-4837be759859", "scored_by": "System", "created_at": "2026-09-25T06:59:25.180503+00:00", "is_override": false, "assessment_id": "b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a", "inherent_rating": 4.00, "override_reason": null, "residual_rating": 3.32, "risk_category_id": "22222222-2222-2222-2222-222222222222", "created_by_user_id": null, "control_ids_credited": [], "control_effectiveness": 0.800, "mitigation_factor_applied": 0.850}	{"residual": 2.5, "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	Vendor has had two prior regulatory findings	2026-09-25 06:59:31.650145+00
81e2be2e-99c2-4c32-b27a-1cee24ec5c8b	298d4e01-a257-407a-9f27-04b96c02ff54	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	Assessment	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	Finalized	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"finalizedBy": "4fa322d3-2245-44ef-b664-1a804442db23"}	\N	2026-09-25 06:59:36.431115+00
343c0c9d-8e3c-4706-a851-37404763a518	298d4e01-a257-407a-9f27-04b96c02ff54	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	ChangeRequest	298d4e01-a257-407a-9f27-04b96c02ff54	Routed	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"status": "PendingCommittee"}	\N	2026-09-25 06:59:36.725326+00
509134c3-8f36-48f9-b0ab-925c86fcfbfc	\N	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	NarrativeSection	f43a13f5-a778-4467-bc61-381babc6c557	AnalystEdited	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "f43a13f5-a778-4467-bc61-381babc6c557", "status": "AnalystEdited", "updated_at": "2026-09-25T06:59:23.520209+00:00", "assessment_id": "b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a", "narrative_text": "QA analyst narrative: vendor in Malta processes cardholder PII via API; enhanced due diligence and contractual audit rights required.", "risk_category_id": "22222222-2222-2222-2222-222222222222", "updated_by_user_id": "4fa322d3-2245-44ef-b664-1a804442db23", "unsupported_claim_flags": []}	{"text": "post-finalize tamper", "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	QA lock test	2026-09-25 06:59:38.616471+00
8b41208c-b546-4f9d-a350-0ba192ed1bd0	\N	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	RiskScore	c3971a0f-a1bd-41ab-b492-4837be759859	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "c3971a0f-a1bd-41ab-b492-4837be759859", "scored_by": "System", "created_at": "2026-09-25T06:59:25.180503+00:00", "is_override": true, "assessment_id": "b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a", "inherent_rating": 4.00, "override_reason": "Vendor has had two prior regulatory findings", "residual_rating": 2.50, "risk_category_id": "22222222-2222-2222-2222-222222222222", "created_by_user_id": null, "control_ids_credited": [], "control_effectiveness": 0.800, "mitigation_factor_applied": 0.850}	{"residual": 0.5, "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	QA lock test	2026-09-25 06:59:38.904162+00
0288d796-0ce6-43ad-9457-7ee088b2867f	\N	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	CategoryMapping	53c6177f-948a-4c2a-a729-7abcdd816a3d	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"isActive": true, "riskCategoryId": "22222222-2222-2222-2222-222222222221"}	QA lock test	2026-09-25 06:59:39.183212+00
2843d3b4-d1e6-47ca-b13c-664448041dea	83f2c245-439e-4b8a-8206-ee1bda436d80	12f0ad4a-87e9-494c-924e-20be52169763	CommitteeVote	f5ff9f57-f1db-4a02-82b8-36f112e39673	Voted	083ecfe5-aa01-4703-9168-762f0065078f	human	\N	{"vote": "ApproveWithConditions", "rationale": null, "conditionsText": ""}	\N	2026-09-25 06:59:41.716251+00
87f59970-5475-488d-ad02-ac9cd5f026e7	83f2c245-439e-4b8a-8206-ee1bda436d80	12f0ad4a-87e9-494c-924e-20be52169763	CommitteeVote	f5ff9f57-f1db-4a02-82b8-36f112e39673	Voted	083ecfe5-aa01-4703-9168-762f0065078f	human	\N	{"vote": "Defer", "rationale": "   ", "conditionsText": null}	\N	2026-09-25 06:59:42.534889+00
2d305f7f-8e6d-4c40-a906-3c21aa911885	83f2c245-439e-4b8a-8206-ee1bda436d80	12f0ad4a-87e9-494c-924e-20be52169763	CommitteeVote	182e5ca3-267e-4dea-9635-8360a86f4521	Voted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"vote": "Approve", "rationale": null, "conditionsText": null}	\N	2026-09-25 06:59:43.314206+00
98d59300-8f4d-4061-ae0b-fe8f380b8b90	83f2c245-439e-4b8a-8206-ee1bda436d80	12f0ad4a-87e9-494c-924e-20be52169763	CommitteeDecision	53aabb7d-9b20-4ece-a088-926ad76fa749	Decisioned	\N	system/AI	\N	{"resolution": "Deferred", "conditionsText": null}	\N	2026-09-25 06:59:43.441949+00
b16762f8-a6fb-4ecd-acaa-44bf23f8bb0b	d80b9214-6103-4950-bbbf-e2ed93d18531	\N	ChangeRequest	d80b9214-6103-4950-bbbf-e2ed93d18531	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609250658] API probe - re-vote", "status": "Submitted", "changeType": "Feature"}	\N	2026-09-25 06:59:45.884143+00
52ff8004-5750-49c3-ab7e-26eac32afb90	d80b9214-6103-4950-bbbf-e2ed93d18531	35b32ea9-b582-47a4-ad59-ad953bc0f5af	Assessment	35b32ea9-b582-47a4-ad59-ad953bc0f5af	Finalized	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"finalizedBy": "4fa322d3-2245-44ef-b664-1a804442db23"}	\N	2026-09-25 06:59:46.528673+00
3932aeb0-6017-4f53-a299-6006c8b45edc	d80b9214-6103-4950-bbbf-e2ed93d18531	35b32ea9-b582-47a4-ad59-ad953bc0f5af	ChangeRequest	d80b9214-6103-4950-bbbf-e2ed93d18531	Routed	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"status": "PendingCommittee"}	\N	2026-09-25 06:59:46.80989+00
34cf7ec6-1e31-4a4e-9756-4940c4af9678	d80b9214-6103-4950-bbbf-e2ed93d18531	35b32ea9-b582-47a4-ad59-ad953bc0f5af	CommitteeVote	a8b460d1-fc19-41d6-9276-9d05081163ab	Voted	083ecfe5-aa01-4703-9168-762f0065078f	human	\N	{"vote": "Approve", "rationale": null, "conditionsText": null}	\N	2026-09-25 06:59:47.152641+00
c40f9874-7b9e-490f-bb4a-1833d5b7f079	d80b9214-6103-4950-bbbf-e2ed93d18531	35b32ea9-b582-47a4-ad59-ad953bc0f5af	CommitteeVote	a8b460d1-fc19-41d6-9276-9d05081163ab	Voted	083ecfe5-aa01-4703-9168-762f0065078f	human	\N	{"vote": "Reject", "rationale": "changed my mind", "conditionsText": null}	\N	2026-09-25 06:59:47.599655+00
3dc207ca-9c7f-4352-8579-37fed4d23dd7	298d4e01-a257-407a-9f27-04b96c02ff54	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	CommitteeVote	bce8b36c-5b4d-4d0d-8b81-d7a46683e18a	Voted	083ecfe5-aa01-4703-9168-762f0065078f	human	\N	{"vote": "ApproveWithConditions", "rationale": null, "conditionsText": "Annual on-site audit of the vendor; PII encrypted at rest"}	\N	2026-09-25 06:59:50.252839+00
a23b973a-5e4a-4e14-93a8-c0e8e7d1efd4	\N	d434153a-e47d-42e2-9009-b9390394d50b	RiskScore	f964fe77-b79e-4968-ae69-640a6affc476	Calculated	\N	system/AI	\N	{"inherent": 3, "residual": 2.200, "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	\N	2026-09-25 07:02:21.764497+00
de8532c3-8361-4cc4-acd0-f75cb9c58e78	\N	\N	ScoringConfig	3046cd30-9350-4d96-a213-0bd2e0286009	ConfigChanged	374a3158-6dfa-41f2-9a4d-3d1091dffacf	human	\N	{"riskCategoryId": "22222222-2222-2222-2222-222222222222", "maxMitigationFactor": 0.85}	QA: restore baseline after TC-API-102	2026-09-25 07:02:22.119103+00
224a6ee0-3bf7-40ae-a7fc-ffdc85464f44	\N	\N	WorkflowRule	d372b4da-a6d2-4921-9aba-35a17aee5055	ConfigChanged	374a3158-6dfa-41f2-9a4d-3d1091dffacf	human	\N	{"ruleKey": "CommitteeQuorum", "ruleValue": {"quorum": 2}}	QA: re-save unchanged value	2026-09-25 07:02:24.934315+00
ab7cf357-43f6-417d-bb9d-576284685f87	9782168a-6d7f-479a-ae0a-ca201f728af2	\N	ChangeRequest	9782168a-6d7f-479a-ae0a-ca201f728af2	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609250702] API probe - actor spoofing", "status": "Submitted", "changeType": "Process"}	\N	2026-09-25 07:02:31.665139+00
98ed14f9-e665-452a-a865-247a405c773e	9782168a-6d7f-479a-ae0a-ca201f728af2	9c444cfb-245b-4b29-9778-592b4a6ea4d2	Assessment	9c444cfb-245b-4b29-9778-592b4a6ea4d2	Finalized	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"finalizedBy": "a6a709a7-65e7-4a90-9b58-cbbaec1d651a"}	\N	2026-09-25 07:02:32.405157+00
4a10b36d-a91c-464b-9d2e-602f6e4edb14	\N	\N	ScoringConfig	18faae4c-c654-4a76-9b9e-0569edb869d9	ConfigChanged	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"riskCategoryId": "22222222-2222-2222-2222-222222222222", "maxMitigationFactor": 0.85}	QA: RBAC probe - value unchanged	2026-09-25 07:02:32.691881+00
6bab4706-d5dc-4e46-aab0-95dff07c5708	fdde906d-fee7-4abe-ab0a-3372b4e0f9b5	\N	ChangeRequest	fdde906d-fee7-4abe-ab0a-3372b4e0f9b5	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609250702] long AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", "status": "Submitted", "changeType": "Feature"}	\N	2026-09-25 07:02:47.355479+00
fbfe7adc-8f59-4ad4-9f25-e763b0267bbd	9c73424d-30b2-4a3e-8881-c25af94572ba	\N	ChangeRequest	9c73424d-30b2-4a3e-8881-c25af94572ba	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609250707] UI lifecycle - onboard Malta settlement vendor", "status": "Submitted", "changeType": "Vendor"}	\N	2026-09-25 07:08:16.035539+00
851fcfaa-860d-4465-8865-a21c53d11e6b	9c73424d-30b2-4a3e-8881-c25af94572ba	\N	ExternalSnapshot	9c73424d-30b2-4a3e-8881-c25af94572ba	Ingested	\N	system	\N	{"hasVendor": true, "hasProduct": false, "hasCustomer": false}	\N	2026-09-25 07:08:16.107116+00
6ce9f157-3e76-42db-ba42-3cde6c3d74a6	9c73424d-30b2-4a3e-8881-c25af94572ba	\N	Attachment	2f251d32-03d7-4e32-a46e-424f1afea090	Uploaded	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"version": 1, "fileName": "vendor-due-diligence.pdf"}	\N	2026-09-25 07:08:21.902721+00
4cbb0612-6cad-4774-b951-08e2671a17f5	9c73424d-30b2-4a3e-8881-c25af94572ba	\N	Attachment	e2fa7fd3-44bd-4b37-8f6c-63786c9ed9e6	Uploaded	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"version": 1, "fileName": "product-spec.docx"}	\N	2026-09-25 07:08:26.93051+00
065f20af-c5dc-4e7e-9080-13ef521306d9	9c73424d-30b2-4a3e-8881-c25af94572ba	\N	Attachment	e1d426f2-d94c-4b66-8926-37b8cc387e76	Uploaded	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"version": 1, "fileName": "control-matrix.xlsx"}	\N	2026-09-25 07:08:32.342311+00
3a939af8-beee-4b1b-af5c-1a30ba7e9987	\N	1de4b6d9-bc92-441c-8299-fe6b4d9fcc2e	CategoryMapping	8de2d092-c99a-416b-9e50-d58129c38433	AiProposed	\N	system/AI	\N	{"citation": "FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Customers", "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	\N	2026-09-25 07:11:50.014946+00
21f1c215-2749-4a1a-bcb3-f5e44831d719	\N	1de4b6d9-bc92-441c-8299-fe6b4d9fcc2e	CategoryMapping	b7227f5e-6ea8-45f6-82ad-4e931b1567ac	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"isActive": true, "riskCategoryId": "22222222-2222-2222-2222-222222222223"}	Vendor domiciled in Malta - geographic exposure (QA)	2026-09-25 07:11:57.954562+00
23224a29-c44c-458c-ba34-472417572181	\N	1de4b6d9-bc92-441c-8299-fe6b4d9fcc2e	CategoryMapping	ac1bb45b-1976-4279-bb68-2463f3319460	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"isActive": true, "riskCategoryId": "22222222-2222-2222-2222-222222222224"}	API integration is a non-face-to-face delivery channel (QA)	2026-09-25 07:11:58.464248+00
337ee377-fc3d-4549-a8c6-9797b2406573	\N	1de4b6d9-bc92-441c-8299-fe6b4d9fcc2e	PolicyReliance	3331b301-8ecc-4984-ab8e-bbf4cf57e72a	Decided	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"decision": "ReliedUpon", "policyChunkId": "af07f40f-b9fa-4614-891b-b0fcc9a8f54b"}	\N	2026-09-25 07:12:04.856541+00
f3a24f8b-91d4-48cd-bd64-48b5c16043e4	\N	1de4b6d9-bc92-441c-8299-fe6b4d9fcc2e	NarrativeSection	68e3a33c-142e-4f32-bd3f-2d5b3376f96a	AiDrafted	\N	system/AI	\N	{"text": "The proposed business change involves onboarding QuickPay Processing Ltd, a Malta-based vendor, as a card settlement processor. This vendor will receive cardholder personally identifiable information (PII) and settlement files through an API. Given that the vendor is a legal entity, this raises considerations aligned with the FFIEC BSA/AML Manual's guidance on risks associated with customer entities, specifically in identifying and verifying the beneficial ownership structure to mitigate money laundering and terrorist financing risks. Although the vendor itself is not a customer per se, it will have access to sensitive customer data, which necessitates thorough due diligence to uncover any complex or opaque ownership that could obscure beneficial owners, consistent with the bank's expectations outlined in the policy excerpt on beneficial ownership verification. The absence of additional extracted facts in this assessment limits the evaluation to this compliance mandate, emphasizing the need for confirmation that QuickPay Processing Ltd's beneficial ownership has been identified and verified to align with regulatory standards.", "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	\N	2026-09-25 07:12:46.431733+00
8ebbd886-b4a9-4ce6-b8c8-84a28fc9c6b1	\N	1de4b6d9-bc92-441c-8299-fe6b4d9fcc2e	NarrativeSection	697bb87d-c1ec-442a-88d0-d22ca6ff82b3	AiDrafted	\N	system/AI	\N	{"text": "The proposed vendor onboarding involves QuickPay Processing Ltd, a card settlement processor based in Malta. According to the FFIEC BSA/AML Manual section on Risks Associated with Money Laundering and Terrorist Financing: Geographic Locations, jurisdictions vary in their risk profiles based on factors such as the effectiveness of anti-money laundering controls and the presence of financial crimes. Malta, as the country of the vendor, represents a geographic consideration in assessing the financial crime risks associated with transmitting cardholder PII and settlement data.\\n\\nGiven the transaction flow involving sensitive personal information and financial data, the bank must evaluate Malta's risk characteristics as defined in the FFIEC guidance. This includes understanding any heightened risks of money laundering or terrorist financing linked to vendors situated in that jurisdiction. Although no specific mitigation measures or additional information are included in the provided facts, adherence to this policy section necessitates that the geographic risk be addressed appropriately during due diligence and ongoing monitoring of the vendor relationship.", "riskCategoryId": "22222222-2222-2222-2222-222222222223"}	\N	2026-09-25 07:12:50.819412+00
69d1b804-e262-4c48-91a9-5e48c4cbdfa9	\N	1de4b6d9-bc92-441c-8299-fe6b4d9fcc2e	RiskScore	6c09555b-b68a-47b2-b681-00a10e438a48	Calculated	\N	system/AI	\N	{"inherent": 3, "residual": 2.5750, "riskCategoryId": "22222222-2222-2222-2222-222222222223"}	\N	2026-09-25 07:13:13.701396+00
c854504a-9095-4397-8c7c-9ce9e4265cd7	6a78af14-7388-4b01-8352-68ebf57be9a6	\N	ChangeRequest	6a78af14-7388-4b01-8352-68ebf57be9a6	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E FINAL09251251] snapshot none", "status": "Submitted", "changeType": "Process"}	\N	2026-09-25 07:22:19.302835+00
e0c73283-3ee0-41fb-b433-c6fde83fff73	ef797803-aaf9-4a7a-b7af-a86f6f010f9a	\N	ChangeRequest	ef797803-aaf9-4a7a-b7af-a86f6f010f9a	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E FINAL09251251] API lifecycle - onboard settlement vendor", "status": "Submitted", "changeType": "Vendor"}	\N	2026-09-25 07:22:21.121384+00
a0c8e3d4-37fc-4ebd-9c23-8a27a6ae6a55	ef797803-aaf9-4a7a-b7af-a86f6f010f9a	\N	ExternalSnapshot	ef797803-aaf9-4a7a-b7af-a86f6f010f9a	Ingested	\N	system	\N	{"hasVendor": true, "hasProduct": false, "hasCustomer": false}	\N	2026-09-25 07:22:21.191721+00
968095f5-d0b7-40df-8036-e0157fa8a847	ef797803-aaf9-4a7a-b7af-a86f6f010f9a	\N	Attachment	bec64b5e-fcf3-4dfb-9805-490a757c5a5c	Uploaded	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"version": 1, "fileName": "vendor-due-diligence.pdf"}	\N	2026-09-25 07:22:21.523301+00
eede4122-c90a-434f-8a29-0506d4fd0392	18404cb0-2e0b-4ef4-9a7d-b06fffe699f5	\N	ChangeRequest	18404cb0-2e0b-4ef4-9a7d-b06fffe699f5	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E FINAL09251251] API probe - empty assessment", "status": "Submitted", "changeType": "Feature"}	\N	2026-09-25 07:22:23.309325+00
72f72c03-67a7-47ac-9f72-2f118d27dce4	\N	1de4b6d9-bc92-441c-8299-fe6b4d9fcc2e	NarrativeSection	68e3a33c-142e-4f32-bd3f-2d5b3376f96a	AnalystEdited	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "68e3a33c-142e-4f32-bd3f-2d5b3376f96a", "status": "AiDrafted", "updated_at": "2026-09-25T07:12:46.431733+00:00", "assessment_id": "1de4b6d9-bc92-441c-8299-fe6b4d9fcc2e", "narrative_text": "The proposed business change involves onboarding QuickPay Processing Ltd, a Malta-based vendor, as a card settlement processor. This vendor will receive cardholder personally identifiable information (PII) and settlement files through an API. Given that the vendor is a legal entity, this raises considerations aligned with the FFIEC BSA/AML Manual's guidance on risks associated with customer entities, specifically in identifying and verifying the beneficial ownership structure to mitigate money laundering and terrorist financing risks. Although the vendor itself is not a customer per se, it will have access to sensitive customer data, which necessitates thorough due diligence to uncover any complex or opaque ownership that could obscure beneficial owners, consistent with the bank's expectations outlined in the policy excerpt on beneficial ownership verification. The absence of additional extracted facts in this assessment limits the evaluation to this compliance mandate, emphasizing the need for confirmation that QuickPay Processing Ltd's beneficial ownership has been identified and verified to align with regulatory standards.", "risk_category_id": "22222222-2222-2222-2222-222222222222", "updated_by_user_id": null, "unsupported_claim_flags": ["The vendor's ownership structure is complex or opaque.", "The vendor presents a heightened risk of facilitating money laundering or terrorist financing.", "The bank has completed the beneficial ownership verification for QuickPay Processing Ltd."]}	{"text": "QA analyst narrative: onboarding a Malta-domiciled settlement processor with API access to cardholder PII. EDD and annual audit rights required.", "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	Added EDD requirement and tightened wording (QA)	2026-09-25 07:13:04.361434+00
af1f8530-74c0-4cb1-ad6a-b3fa023b2c2c	\N	1de4b6d9-bc92-441c-8299-fe6b4d9fcc2e	NarrativeSection	697bb87d-c1ec-442a-88d0-d22ca6ff82b3	AnalystReviewed	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"status": "AnalystReviewed", "riskCategoryId": "22222222-2222-2222-2222-222222222223"}	\N	2026-09-25 07:13:05.354451+00
5a62e96e-b650-4338-abc4-0c934a778f3d	\N	1de4b6d9-bc92-441c-8299-fe6b4d9fcc2e	RiskScore	46bd005e-9d1b-4ade-b319-c2397b25913d	Calculated	\N	system/AI	\N	{"inherent": 5, "residual": 4.150, "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	\N	2026-09-25 07:13:12.518319+00
d3d019ad-43dc-4500-98bf-d137eb2b3dd6	\N	1de4b6d9-bc92-441c-8299-fe6b4d9fcc2e	RiskScore	46bd005e-9d1b-4ade-b319-c2397b25913d	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "46bd005e-9d1b-4ade-b319-c2397b25913d", "scored_by": "System", "created_at": "2026-09-25T07:13:12.518319+00:00", "is_override": false, "assessment_id": "1de4b6d9-bc92-441c-8299-fe6b4d9fcc2e", "inherent_rating": 5.00, "override_reason": null, "residual_rating": 4.15, "risk_category_id": "22222222-2222-2222-2222-222222222222", "created_by_user_id": null, "control_ids_credited": [], "control_effectiveness": 1.000, "mitigation_factor_applied": 0.850}	{"residual": 2.5, "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	Vendor had prior regulatory findings (QA)	2026-09-25 07:13:30.354258+00
18387e20-ca04-4b54-897a-f58a7ed645d6	\N	\N	WorkflowRule	d2418460-1ad5-418c-bc0f-aded1d1a025c	ConfigChanged	374a3158-6dfa-41f2-9a4d-3d1091dffacf	human	\N	{"ruleKey": "CommitteeQuorum", "ruleValue": {"quorum": 2}}	QA: re-save unchanged quorum	2026-09-25 07:20:12.71744+00
ce3f1be8-fa15-4cbf-844c-5194943c025b	\N	\N	ScoringConfig	64715f64-1a26-4179-a75b-0120f9f7c0cf	ConfigChanged	374a3158-6dfa-41f2-9a4d-3d1091dffacf	human	\N	{"riskCategoryId": "22222222-2222-2222-2222-222222222222", "maxMitigationFactor": 0.85}	QA: re-save unchanged baseline	2026-09-25 07:20:17.960013+00
e3899a7d-0fad-4d66-aa6f-8472748bc1de	a4614f58-6f4f-45bf-92fb-1d652866657e	\N	ChangeRequest	a4614f58-6f4f-45bf-92fb-1d652866657e	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609250720] <img src=x onerror=\\"window.__xss=1\\"><script>window.__xss=2</script>", "status": "Submitted", "changeType": "Feature"}	\N	2026-09-25 07:20:20.08475+00
4ae8d821-46ff-4df3-ac71-7535604888b6	7e97dfcc-50bd-40a8-b0cb-5db666f40111	\N	ChangeRequest	7e97dfcc-50bd-40a8-b0cb-5db666f40111	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E FINAL09251251] API intake - prepaid card", "status": "Submitted", "changeType": "Product"}	\N	2026-09-25 07:21:58.094958+00
f8d0d249-0176-45df-a54e-198847773a0b	7e97dfcc-50bd-40a8-b0cb-5db666f40111	\N	ExternalSnapshot	7e97dfcc-50bd-40a8-b0cb-5db666f40111	Ingested	\N	system	\N	{"hasVendor": false, "hasProduct": true, "hasCustomer": false}	\N	2026-09-25 07:21:58.176392+00
8b15fb47-04f0-4f51-bbbe-42d67551b35f	83fd772d-e35b-4f9c-9d75-c4064841e157	\N	ChangeRequest	83fd772d-e35b-4f9c-9d75-c4064841e157	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E FINAL09251251] type Product", "status": "Submitted", "changeType": "Product"}	\N	2026-09-25 07:21:59.081579+00
fe3caf87-aeaa-48b5-8016-0aa4ca7eb639	c2f156eb-e295-44e9-ad78-723a35feefb8	\N	ChangeRequest	c2f156eb-e295-44e9-ad78-723a35feefb8	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E FINAL09251251] type Feature", "status": "Submitted", "changeType": "Feature"}	\N	2026-09-25 07:21:59.387397+00
07790956-a08a-414b-8176-0db97f7ee9e9	f0ce4db6-ca13-4f7c-a468-d6651c2e34be	\N	ChangeRequest	f0ce4db6-ca13-4f7c-a468-d6651c2e34be	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E FINAL09251251] type Process", "status": "Submitted", "changeType": "Process"}	\N	2026-09-25 07:21:59.698513+00
37779f6a-a574-4897-af9c-60dfe107ac34	efbde630-cc1f-4931-8635-0941776edec5	\N	ChangeRequest	efbde630-cc1f-4931-8635-0941776edec5	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E FINAL09251251] type Vendor", "status": "Submitted", "changeType": "Vendor"}	\N	2026-09-25 07:21:59.987346+00
26307013-235e-49ea-8ed0-f864abad1cf3	1574b600-6773-46a4-a30e-1f7664101fc1	\N	ChangeRequest	1574b600-6773-46a4-a30e-1f7664101fc1	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E FINAL09251251] type Geography", "status": "Submitted", "changeType": "Geography"}	\N	2026-09-25 07:22:00.28372+00
7e8536f5-6b5e-4c44-ac26-6471109503df	be27434a-b46d-4f8c-8f97-790e413248f7	\N	ChangeRequest	be27434a-b46d-4f8c-8f97-790e413248f7	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E FINAL09251251] type CustomerSegment", "status": "Submitted", "changeType": "CustomerSegment"}	\N	2026-09-25 07:22:00.584982+00
4bfc8343-5cc4-4db0-9098-b5572927ddea	fc726513-8a52-42e1-a104-fcbf7d023ab2	\N	ChangeRequest	fc726513-8a52-42e1-a104-fcbf7d023ab2	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "", "status": "Submitted", "changeType": "Product"}	\N	2026-09-25 07:22:02.524814+00
73f07fc9-61ed-485d-ae70-7b3342737e90	9c895ced-c6aa-44af-a2f3-d7d96fb72c43	\N	ChangeRequest	9c895ced-c6aa-44af-a2f3-d7d96fb72c43	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E FINAL09251251] attachments", "status": "Submitted", "changeType": "Vendor"}	\N	2026-09-25 07:22:10.907194+00
fcc7e950-c171-44da-ba9e-606d11be617f	9c895ced-c6aa-44af-a2f3-d7d96fb72c43	\N	Attachment	f707d937-1e2a-41ce-a4d8-f2d6a6843f03	Uploaded	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"version": 1, "fileName": "vendor-due-diligence.pdf"}	\N	2026-09-25 07:22:11.282918+00
0e8e1be1-83f9-4641-b27c-6012c22c6a72	9c895ced-c6aa-44af-a2f3-d7d96fb72c43	\N	Attachment	f1644753-11c1-4cf8-bad3-cd758f6ca7f1	Uploaded	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"version": 1, "fileName": "product-spec.docx"}	\N	2026-09-25 07:22:11.617289+00
60e1f1df-0f67-43b7-94b6-a7b59db0c22e	9c895ced-c6aa-44af-a2f3-d7d96fb72c43	\N	Attachment	72abff8e-2572-4136-b919-454bf79fbaae	Uploaded	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"version": 1, "fileName": "control-matrix.xlsx"}	\N	2026-09-25 07:22:11.924679+00
9c488c16-1835-4e91-b814-a6f21656eca9	7a6ea15a-41be-4f29-9882-0921a6ffbe48	\N	ChangeRequest	7a6ea15a-41be-4f29-9882-0921a6ffbe48	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E FINAL09251251] bad uploads", "status": "Submitted", "changeType": "Vendor"}	\N	2026-09-25 07:22:14.640162+00
c1526a5f-6785-4e0d-b178-5c1a8c68be60	7a6ea15a-41be-4f29-9882-0921a6ffbe48	\N	Attachment	6aaa2f77-6005-46ec-a4ed-4b47a76a5d83	Uploaded	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"version": 1, "fileName": "malicious.exe"}	\N	2026-09-25 07:22:15.487132+00
72c95617-659c-4aaa-b81d-da330e24070e	ba127540-de51-4e40-989e-29b7bb56ec57	\N	ChangeRequest	ba127540-de51-4e40-989e-29b7bb56ec57	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E FINAL09251251] clarification", "status": "Submitted", "changeType": "Geography"}	\N	2026-09-25 07:22:17.418978+00
c82ded01-0ad2-446a-abbc-e3695b4a51ce	ba127540-de51-4e40-989e-29b7bb56ec57	\N	Clarification	7be6b406-d0e6-4907-aa52-7afc7ea12b65	Requested	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"question": "Which target countries exactly?"}	\N	2026-09-25 07:22:17.719042+00
306da681-403d-4332-8e0c-9b0307e49a62	91d32e88-acb4-4f61-9053-e7ce06c9f89f	\N	ChangeRequest	91d32e88-acb4-4f61-9053-e7ce06c9f89f	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E FINAL09251251] snapshot linked", "status": "Submitted", "changeType": "Product"}	\N	2026-09-25 07:22:18.92203+00
d12504af-2d3c-4f57-b4ef-1fe8e84a7fd3	91d32e88-acb4-4f61-9053-e7ce06c9f89f	\N	ExternalSnapshot	91d32e88-acb4-4f61-9053-e7ce06c9f89f	Ingested	\N	system	\N	{"hasVendor": false, "hasProduct": true, "hasCustomer": false}	\N	2026-09-25 07:22:18.99228+00
e06344d6-06ed-46e7-b050-d05857b1f81f	18404cb0-2e0b-4ef4-9a7d-b06fffe699f5	50f965f9-70e5-4c4d-bec5-36017302898e	Assessment	50f965f9-70e5-4c4d-bec5-36017302898e	Finalized	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"finalizedBy": "4fa322d3-2245-44ef-b664-1a804442db23"}	\N	2026-09-25 07:22:24.397786+00
b9e2de92-57ee-42e5-be3c-1724fe3f67c0	18404cb0-2e0b-4ef4-9a7d-b06fffe699f5	50f965f9-70e5-4c4d-bec5-36017302898e	ChangeRequest	18404cb0-2e0b-4ef4-9a7d-b06fffe699f5	Routed	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"status": "PendingCommittee"}	\N	2026-09-25 07:22:24.703387+00
26def3b7-bc0f-4c98-814f-cc0d595394f6	\N	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	CategoryMapping	3104cd90-9650-45c0-ba54-a0c69f1512e4	AiProposed	\N	system/AI	\N	{"citation": "FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Customers", "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	\N	2026-09-25 07:22:28.181692+00
81ef379f-9f6a-45b6-b239-f86031ae0e8a	\N	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	CategoryMapping	50856e97-3118-4319-8d00-bea81ee5e589	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"isActive": true, "riskCategoryId": "22222222-2222-2222-2222-222222222223"}	Vendor is domiciled in Malta - geographic exposure	2026-09-25 07:22:30.50241+00
378a5310-b42e-4465-ad2f-8c64ad9268a5	\N	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	CategoryMapping	aafa75fc-965b-4f03-bc3e-d02c0f89aa81	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"isActive": false, "riskCategoryId": "22222222-2222-2222-2222-222222222224"}	QA: removal test	2026-09-25 07:22:30.814147+00
65d9d702-d89d-4a28-9f55-d43033871923	\N	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	CategoryMapping	aafa75fc-965b-4f03-bc3e-d02c0f89aa81	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "aafa75fc-965b-4f03-bc3e-d02c0f89aa81", "source": "AnalystAdded", "is_active": false, "created_at": "2026-09-25T07:22:30.814147+00:00", "ai_citation": null, "assessment_id": "eba39f9c-a4ba-40cf-946d-fa0a3da1bb98", "risk_category_id": "22222222-2222-2222-2222-222222222224", "created_by_user_id": "4fa322d3-2245-44ef-b664-1a804442db23"}	{"isActive": true, "riskCategoryId": "22222222-2222-2222-2222-222222222224"}	QA: restore - API channel is non-face-to-face	2026-09-25 07:22:31.128224+00
d30ef279-151a-4d3e-a16c-84c1e650cc21	\N	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	PolicyReliance	dd0edbb8-1852-48e5-814e-319bd2f44f18	Decided	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"decision": "ReliedUpon", "policyChunkId": "3f171e93-f2ca-40a4-af6a-18ede9021c9b"}	\N	2026-09-25 07:22:40.963481+00
cfd56c86-fad7-4d81-a3c1-33a7a8f95622	\N	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	PolicyReliance	13789a14-dbae-4c63-bb86-9043d5e273ab	Decided	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"decision": "ReliedUpon", "policyChunkId": "539e307e-5d18-454b-a33c-fbcf3ff8c407"}	\N	2026-09-25 07:22:41.280105+00
06303de0-d152-4f8a-85c4-8415728a14b0	\N	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	PolicyReliance	e215d692-fa83-4f3e-8be6-58731f580516	Decided	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"decision": "ReliedUpon", "policyChunkId": "8fc9b915-62af-410e-af73-373e51aac522"}	\N	2026-09-25 07:22:41.579402+00
dd6be633-98e9-4ac8-be2d-481ee4a2f0a7	\N	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	PolicyReliance	ee986728-74a5-4b0e-9649-8772ffaabb96	Decided	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"decision": "NotRelevant", "policyChunkId": "af07f40f-b9fa-4614-891b-b0fcc9a8f54b"}	\N	2026-09-25 07:22:41.887079+00
59053042-3817-4945-a120-3f22d999cd91	\N	50f965f9-70e5-4c4d-bec5-36017302898e	PolicyReliance	fa89511e-927e-4f91-b3a4-1168a983f4ba	Decided	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"decision": "ReliedUpon", "policyChunkId": "3f171e93-f2ca-40a4-af6a-18ede9021c9b"}	\N	2026-09-25 07:22:44.657604+00
a4618126-3962-415d-ac71-574747e3a3d5	\N	50f965f9-70e5-4c4d-bec5-36017302898e	PolicyReliance	fa89511e-927e-4f91-b3a4-1168a983f4ba	Decided	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"decision": "ReliedUpon", "policyChunkId": "3f171e93-f2ca-40a4-af6a-18ede9021c9b"}	\N	2026-09-25 07:22:44.989794+00
e232c273-7de3-4c73-8381-d75d097659c2	ef797803-aaf9-4a7a-b7af-a86f6f010f9a	\N	ExtractedField	f6778bcd-f06c-457f-ab03-3bba2471ec7f	AiExtracted	\N	system/AI	\N	{"value": "QuickPay Processing Ltd", "fieldKey": "vendor_name", "confidence": 1, "needsReview": false}	\N	2026-09-25 07:22:49.272369+00
9d0958d0-208d-4fb0-a85d-3e4b9216ab4d	ef797803-aaf9-4a7a-b7af-a86f6f010f9a	\N	ExtractedField	6c02deaf-9b1c-47ed-b377-c781a4e508c9	AiExtracted	\N	system/AI	\N	{"value": "Malta", "fieldKey": "vendor_jurisdiction", "confidence": 1, "needsReview": false}	\N	2026-09-25 07:22:49.306233+00
3d95c841-61e1-45d1-8dce-5f312f9c20e8	ef797803-aaf9-4a7a-b7af-a86f6f010f9a	\N	ExtractedField	77882651-65c8-49d0-b0aa-9e7fe938daee	AiExtracted	\N	system/AI	\N	{"value": "cardholder PII and settlement files", "fieldKey": "data_access_scope", "confidence": 1, "needsReview": false}	\N	2026-09-25 07:22:49.338997+00
da999df3-dd2b-4b9e-a3ca-f5ffaadcdedd	ef797803-aaf9-4a7a-b7af-a86f6f010f9a	\N	ExtractedField	477bd9fe-ca0e-4e34-b2b7-018adf0f114c	AiExtracted	\N	system/AI	\N	{"value": "retail cardholders, MSB merchants", "fieldKey": "customer_types_affected", "confidence": 1, "needsReview": false}	\N	2026-09-25 07:22:49.371374+00
caee36a9-541f-40a4-abac-f18e1e30782e	ef797803-aaf9-4a7a-b7af-a86f6f010f9a	\N	ExtractedField	85804a91-c955-43d2-a964-1f0273b36ce1	AiExtracted	\N	system/AI	\N	{"value": "API, non-face-to-face", "fieldKey": "delivery_channel", "confidence": 1, "needsReview": false}	\N	2026-09-25 07:22:49.40569+00
4a91b36a-9684-46fe-a25a-8c90e351341f	ef797803-aaf9-4a7a-b7af-a86f6f010f9a	\N	ExtractedField	f6778bcd-f06c-457f-ab03-3bba2471ec7f	Corrected	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "f6778bcd-f06c-457f-ab03-3bba2471ec7f", "source": "AiExtracted", "field_key": "vendor_name", "confidence": 1.000, "updated_at": "2026-09-25T07:22:49.272369+00:00", "field_value": "QuickPay Processing Ltd", "needs_review": false, "attachment_id": "bec64b5e-fcf3-4dfb-9805-490a757c5a5c", "source_excerpt": "Vendor name: QuickPay Processing Ltd", "change_request_id": "ef797803-aaf9-4a7a-b7af-a86f6f010f9a", "updated_by_user_id": null}	{"value": "QA value ", "fieldKey": "vendor_name"}	\N	2026-09-25 07:22:51.065846+00
dabfd57c-0f9e-473f-9ed5-7d6802682835	ef797803-aaf9-4a7a-b7af-a86f6f010f9a	\N	ExtractedField	f6778bcd-f06c-457f-ab03-3bba2471ec7f	Corrected	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "f6778bcd-f06c-457f-ab03-3bba2471ec7f", "source": "AnalystCorrected", "field_key": "vendor_name", "confidence": null, "updated_at": "2026-09-25T07:22:51.065846+00:00", "field_value": "QA value ", "needs_review": false, "attachment_id": "bec64b5e-fcf3-4dfb-9805-490a757c5a5c", "source_excerpt": "Vendor name: QuickPay Processing Ltd", "change_request_id": "ef797803-aaf9-4a7a-b7af-a86f6f010f9a", "updated_by_user_id": "4fa322d3-2245-44ef-b664-1a804442db23"}	{"value": "QA corrected value", "fieldKey": "vendor_name"}	Contract section 4 states otherwise	2026-09-25 07:22:51.402529+00
57ba3167-24f6-49ef-bee8-309f5ccc324d	\N	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	NarrativeSection	a4483065-c1c3-4d27-8aa8-421a0a6dff45	AiDrafted	\N	system/AI	\N	{"text": "The proposed business change involves onboarding QA corrected value, a Malta-based card settlement processor, which will have access to sensitive customer data including cardholder Personally Identifiable Information (PII) and settlement files. Given this processor's jurisdiction in Malta and the nature of the data access scope, there is an inherent risk related to the confidentiality and security of customer information, particularly involving retail cardholders and Money Services Business (MSB) merchants. The delivery channel for settlement processing will be through API without face-to-face contact, which aligns with categories of products and services identified in the FFIEC BSA/AML Manual as vulnerable to money laundering risks due to rapid movement of funds and limited physical interaction (Risks Associated with Money Laundering and Terrorist Financing - Products and Services).", "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	\N	2026-09-25 07:22:55.591763+00
29ad3ac8-4207-4db8-9c3f-06ce486c856c	\N	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	NarrativeSection	d41ca34c-ab7b-4f0b-81f9-fc03ca6af113	AiDrafted	\N	system/AI	\N	{"text": "The proposed change involves onboarding a Malta-based card settlement processor, QA corrected value, which will have access to cardholder PII and settlement files. This vendor will serve retail cardholders and MSB merchants through an API delivery channel, which is a non-face-to-face method. According to the FFIEC BSA/AML Manual on Risks Associated with Money Laundering and Terrorist Financing, non-face-to-face delivery channels, including reliance on third-party agents or correspondent relationships to deliver products, reduce a bank's ability to verify customer identity and intent directly, thereby increasing risk (Delivery Channels). Given that Malta is the vendor jurisdiction, it is critical to consider the geographic risk factors associated with operating in or contracting with vendors in that location, as outlined in the supervisory citation for Geographic Locations.", "riskCategoryId": "22222222-2222-2222-2222-222222222223"}	\N	2026-09-25 07:22:58.60826+00
eda9b36b-b831-4af6-bc99-17772a06b23f	\N	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	NarrativeSection	07c0ea68-5e6e-4418-af8d-1115d57822d0	AiDrafted	\N	system/AI	\N	{"text": "The proposed vendor onboarding involves a Malta-based card settlement processor, QA corrected value, which will access cardholder personally identifiable information (PII) and settlement files through an API delivery channel. This onboarding represents a non-face-to-face delivery channel, which inherently carries risk considerations for money laundering and terrorist financing due to the lack of in-person verification. As noted in the FFIEC BSA/AML Manual, delivery channels such as APIs facilitating remote transactions necessitate heightened vigilance in monitoring for suspicious activity (Delivery Channels section).\\n\\nGiven that Malta is a foreign jurisdiction, this relationship may be analogously considered in light of correspondent banking risk principles related to foreign financial institutions. Specifically, the policy excerpt emphasizes enhanced due diligence for foreign correspondent relationships, especially in higher-risk jurisdictions (Risks Associated with Money Laundering and Terrorist Financing - Correspondent Banking). While Malta is not explicitly classified here, the principle of assessing the adequacy of the vendor's AML controls and monitoring the transaction patterns remains critical.\\n\\nThe affected customer types include retail cardholders and MSB merchants, both of which could present diverse risk profiles. Accordingly, robust AML controls and continuous monitoring of transaction activity flowing through this API-based settlement vendor should be maintained to effectively mitigate delivery channel risks and align with the supervisory expectations delineated in the FFIEC guidance.", "riskCategoryId": "22222222-2222-2222-2222-222222222224"}	\N	2026-09-25 07:23:02.425645+00
79311df0-1856-46f7-a388-fcab40060635	\N	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	NarrativeSection	a4483065-c1c3-4d27-8aa8-421a0a6dff45	AiDrafted	\N	system/AI	{"id": "a4483065-c1c3-4d27-8aa8-421a0a6dff45", "status": "AiDrafted", "updated_at": "2026-09-25T07:22:55.591763+00:00", "assessment_id": "eba39f9c-a4ba-40cf-946d-fa0a3da1bb98", "narrative_text": "The proposed business change involves onboarding QA corrected value, a Malta-based card settlement processor, which will have access to sensitive customer data including cardholder Personally Identifiable Information (PII) and settlement files. Given this processor's jurisdiction in Malta and the nature of the data access scope, there is an inherent risk related to the confidentiality and security of customer information, particularly involving retail cardholders and Money Services Business (MSB) merchants. The delivery channel for settlement processing will be through API without face-to-face contact, which aligns with categories of products and services identified in the FFIEC BSA/AML Manual as vulnerable to money laundering risks due to rapid movement of funds and limited physical interaction (Risks Associated with Money Laundering and Terrorist Financing - Products and Services).", "risk_category_id": "22222222-2222-2222-2222-222222222222", "updated_by_user_id": null, "unsupported_claim_flags": []}	{"text": "The onboarding of the Malta-based settlement vendor, QA corrected value, introduces specific risks related to the handling of cardholder PII and settlement files, accessed via an API-based, non-face-to-face delivery channel. Given the vendor's jurisdiction and the involvement of retail cardholders and MSB merchants, this change requires careful assessment under the FFIEC BSA/AML Manual's guidance on risks associated with customers and entities. Consistent with the policy section on Products and Services, the vendor's role facilitates rapid movement of funds and limited face-to-face interaction, both factors increasing money laundering vulnerability. The bank must ensure it has identified, measured, and implemented adequate risk mitigation controls before onboarding this service to address these inherent risks.", "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	\N	2026-09-25 07:23:07.113278+00
bde4e6ef-fc29-4b20-ae91-fa24625bda6a	\N	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	NarrativeSection	a4483065-c1c3-4d27-8aa8-421a0a6dff45	AnalystEdited	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "a4483065-c1c3-4d27-8aa8-421a0a6dff45", "status": "AiDrafted", "updated_at": "2026-09-25T07:23:07.113278+00:00", "assessment_id": "eba39f9c-a4ba-40cf-946d-fa0a3da1bb98", "narrative_text": "The onboarding of the Malta-based settlement vendor, QA corrected value, introduces specific risks related to the handling of cardholder PII and settlement files, accessed via an API-based, non-face-to-face delivery channel. Given the vendor's jurisdiction and the involvement of retail cardholders and MSB merchants, this change requires careful assessment under the FFIEC BSA/AML Manual's guidance on risks associated with customers and entities. Consistent with the policy section on Products and Services, the vendor's role facilitates rapid movement of funds and limited face-to-face interaction, both factors increasing money laundering vulnerability. The bank must ensure it has identified, measured, and implemented adequate risk mitigation controls before onboarding this service to address these inherent risks.", "risk_category_id": "22222222-2222-2222-2222-222222222222", "updated_by_user_id": null, "unsupported_claim_flags": []}	{"text": "QA analyst narrative: vendor in Malta processes cardholder PII via API; enhanced due diligence and contractual audit rights required.", "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	Tightened wording and added EDD requirement	2026-09-25 07:23:09.036487+00
7d40b70b-01aa-4c59-8d33-ac06a0b0dd31	\N	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	NarrativeSection	d41ca34c-ab7b-4f0b-81f9-fc03ca6af113	AnalystReviewed	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"status": "AnalystReviewed", "riskCategoryId": "22222222-2222-2222-2222-222222222223"}	\N	2026-09-25 07:23:09.320051+00
02d911ba-da22-4090-a81e-0c90d9f35efd	\N	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	NarrativeSection	07c0ea68-5e6e-4418-af8d-1115d57822d0	AnalystReviewed	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"status": "AnalystReviewed", "riskCategoryId": "22222222-2222-2222-2222-222222222224"}	\N	2026-09-25 07:23:09.601868+00
ecd1adbb-da87-4806-a839-197a90f9a980	\N	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	RiskScore	c3ce38ba-bbcb-41e2-b277-d745d739d730	Calculated	\N	system/AI	\N	{"inherent": 4, "residual": 3.3200, "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	\N	2026-09-25 07:23:10.717857+00
480f6058-cc38-4e84-af4a-aa90d670b3b0	\N	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	RiskScore	1912a7b8-c573-4f2e-a1e0-8f2b5d498f2f	Calculated	\N	system/AI	\N	{"inherent": 1, "residual": 0.150, "riskCategoryId": "22222222-2222-2222-2222-222222222223"}	\N	2026-09-25 07:23:11.046329+00
132152f6-3956-4f43-ae44-a9e8bf0777dd	\N	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	RiskScore	81dd2e07-f2e3-4eb3-901d-101e14fb51b8	Calculated	\N	system/AI	\N	{"inherent": 3, "residual": 2.5750, "riskCategoryId": "22222222-2222-2222-2222-222222222224"}	\N	2026-09-25 07:23:11.382468+00
d12ae6e7-0602-45cb-9b0a-0ade7e24ead5	\N	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	RiskScore	c3ce38ba-bbcb-41e2-b277-d745d739d730	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "c3ce38ba-bbcb-41e2-b277-d745d739d730", "scored_by": "System", "created_at": "2026-09-25T07:23:10.717857+00:00", "is_override": false, "assessment_id": "eba39f9c-a4ba-40cf-946d-fa0a3da1bb98", "inherent_rating": 4.00, "override_reason": null, "residual_rating": 3.32, "risk_category_id": "22222222-2222-2222-2222-222222222222", "created_by_user_id": null, "control_ids_credited": [], "control_effectiveness": 0.800, "mitigation_factor_applied": 0.850}	{"residual": 2.5, "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	Vendor has had two prior regulatory findings	2026-09-25 07:23:16.22897+00
b5a47c34-8570-44bd-bc6e-5982cc2cce6e	ef797803-aaf9-4a7a-b7af-a86f6f010f9a	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	Assessment	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	Finalized	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"finalizedBy": "4fa322d3-2245-44ef-b664-1a804442db23"}	\N	2026-09-25 07:23:22.966726+00
88fc101b-619a-4f93-9297-cbf85ab093df	ef797803-aaf9-4a7a-b7af-a86f6f010f9a	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	ChangeRequest	ef797803-aaf9-4a7a-b7af-a86f6f010f9a	Routed	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"status": "PendingCommittee"}	\N	2026-09-25 07:23:23.27321+00
35e8e899-fafc-46d4-b17d-0705494b61fe	507e6f32-ab80-40db-81bd-5f641ef033a4	\N	Attachment	1cda1ab4-a509-4f5d-877a-0660fbc6e2fa	Uploaded	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"version": 1, "fileName": "control-matrix.xlsx"}	\N	2026-09-25 07:25:44.902114+00
3cf183f2-313a-44a0-8730-b1b5a5f5b206	\N	\N	WorkflowRule	070ffe5e-7463-4116-bb16-a8787417db31	ConfigChanged	374a3158-6dfa-41f2-9a4d-3d1091dffacf	human	\N	{"ruleKey": "CommitteeQuorum", "ruleValue": {"quorum": 2}}	QA: re-save unchanged quorum	2026-09-25 07:29:47.116385+00
bb960964-6908-4867-8773-9ea2006b7fae	\N	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	NarrativeSection	a4483065-c1c3-4d27-8aa8-421a0a6dff45	AnalystEdited	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "a4483065-c1c3-4d27-8aa8-421a0a6dff45", "status": "AnalystEdited", "updated_at": "2026-09-25T07:23:09.036487+00:00", "assessment_id": "eba39f9c-a4ba-40cf-946d-fa0a3da1bb98", "narrative_text": "QA analyst narrative: vendor in Malta processes cardholder PII via API; enhanced due diligence and contractual audit rights required.", "risk_category_id": "22222222-2222-2222-2222-222222222222", "updated_by_user_id": "4fa322d3-2245-44ef-b664-1a804442db23", "unsupported_claim_flags": []}	{"text": "post-finalize tamper", "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	QA lock test	2026-09-25 07:23:25.253252+00
50affdfc-5edf-4e16-b79b-f50da9cd7ce8	\N	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	RiskScore	c3ce38ba-bbcb-41e2-b277-d745d739d730	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "c3ce38ba-bbcb-41e2-b277-d745d739d730", "scored_by": "System", "created_at": "2026-09-25T07:23:10.717857+00:00", "is_override": true, "assessment_id": "eba39f9c-a4ba-40cf-946d-fa0a3da1bb98", "inherent_rating": 4.00, "override_reason": "Vendor has had two prior regulatory findings", "residual_rating": 2.50, "risk_category_id": "22222222-2222-2222-2222-222222222222", "created_by_user_id": null, "control_ids_credited": [], "control_effectiveness": 0.800, "mitigation_factor_applied": 0.850}	{"residual": 0.5, "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	QA lock test	2026-09-25 07:23:25.564516+00
39e23b64-a78a-459c-9edb-50d1b2798927	\N	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	CategoryMapping	644784b9-f43a-4f67-9197-3ee3df47709c	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"isActive": true, "riskCategoryId": "22222222-2222-2222-2222-222222222221"}	QA lock test	2026-09-25 07:23:25.85331+00
6edddd04-ad4e-45e9-8320-219273648b92	18404cb0-2e0b-4ef4-9a7d-b06fffe699f5	50f965f9-70e5-4c4d-bec5-36017302898e	CommitteeVote	e0e39fce-7476-4503-a59c-97bc587cde38	Voted	083ecfe5-aa01-4703-9168-762f0065078f	human	\N	{"vote": "ApproveWithConditions", "rationale": null, "conditionsText": ""}	\N	2026-09-25 07:23:28.273369+00
c6641176-83a0-46d5-b399-653725ef259f	18404cb0-2e0b-4ef4-9a7d-b06fffe699f5	50f965f9-70e5-4c4d-bec5-36017302898e	CommitteeVote	e0e39fce-7476-4503-a59c-97bc587cde38	Voted	083ecfe5-aa01-4703-9168-762f0065078f	human	\N	{"vote": "Defer", "rationale": "   ", "conditionsText": null}	\N	2026-09-25 07:23:29.104309+00
1dfa39de-8804-4e19-a362-5b1a2f1d21d7	18404cb0-2e0b-4ef4-9a7d-b06fffe699f5	50f965f9-70e5-4c4d-bec5-36017302898e	CommitteeVote	49503cc7-0fe9-4d97-a8a9-cf7177d20505	Voted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"vote": "Approve", "rationale": null, "conditionsText": null}	\N	2026-09-25 07:23:29.899815+00
f25fae25-2ed4-4021-a27f-d3b5092f608d	18404cb0-2e0b-4ef4-9a7d-b06fffe699f5	50f965f9-70e5-4c4d-bec5-36017302898e	CommitteeDecision	aafde869-a249-41d5-b790-c6fed1ff4f27	Decisioned	\N	system/AI	\N	{"resolution": "Deferred", "conditionsText": null}	\N	2026-09-25 07:23:30.023872+00
9e3cb07c-3e0e-472d-a7f8-ce8b7fc28b4f	b1c408c0-01d2-4d51-b5e9-20cb5fdfba0a	\N	ChangeRequest	b1c408c0-01d2-4d51-b5e9-20cb5fdfba0a	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E FINAL09251251] API probe - re-vote", "status": "Submitted", "changeType": "Feature"}	\N	2026-09-25 07:23:33.329633+00
92f0f048-8990-42c6-893d-54b4ba0d4ba8	b1c408c0-01d2-4d51-b5e9-20cb5fdfba0a	25ab4813-e18f-49c9-a50e-8541b5d63a10	Assessment	25ab4813-e18f-49c9-a50e-8541b5d63a10	Finalized	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"finalizedBy": "4fa322d3-2245-44ef-b664-1a804442db23"}	\N	2026-09-25 07:23:34.030714+00
19cc818d-b8b2-4a5a-9450-6edbd73aabf7	b1c408c0-01d2-4d51-b5e9-20cb5fdfba0a	25ab4813-e18f-49c9-a50e-8541b5d63a10	ChangeRequest	b1c408c0-01d2-4d51-b5e9-20cb5fdfba0a	Routed	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"status": "PendingCommittee"}	\N	2026-09-25 07:23:34.3205+00
1f0922a1-10a3-4821-9134-562dddc8c890	b1c408c0-01d2-4d51-b5e9-20cb5fdfba0a	25ab4813-e18f-49c9-a50e-8541b5d63a10	CommitteeVote	90d10b72-34ab-4700-8eee-2e4e68b76145	Voted	083ecfe5-aa01-4703-9168-762f0065078f	human	\N	{"vote": "Approve", "rationale": null, "conditionsText": null}	\N	2026-09-25 07:23:34.68056+00
81de8856-f39d-4b58-bc56-77f85ea25fcd	b1c408c0-01d2-4d51-b5e9-20cb5fdfba0a	25ab4813-e18f-49c9-a50e-8541b5d63a10	CommitteeVote	90d10b72-34ab-4700-8eee-2e4e68b76145	Voted	083ecfe5-aa01-4703-9168-762f0065078f	human	\N	{"vote": "Reject", "rationale": "changed my mind", "conditionsText": null}	\N	2026-09-25 07:23:35.129533+00
8c579558-e654-41c8-b338-628dae0ee182	ef797803-aaf9-4a7a-b7af-a86f6f010f9a	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	CommitteeVote	3a49fa0e-830d-4b3b-ae75-977b8d77c818	Voted	083ecfe5-aa01-4703-9168-762f0065078f	human	\N	{"vote": "ApproveWithConditions", "rationale": null, "conditionsText": "Annual on-site audit of the vendor; PII encrypted at rest"}	\N	2026-09-25 07:23:37.930855+00
39cc7375-457f-4697-b675-7fae55643dfb	ef797803-aaf9-4a7a-b7af-a86f6f010f9a	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	CommitteeVote	2c433f59-84a4-46a5-ab83-b6aff078bcda	Voted	fa142c1c-58cc-4666-b135-7768a2ab33f0	human	\N	{"vote": "Approve", "rationale": null, "conditionsText": null}	\N	2026-09-25 07:23:38.383984+00
97c73660-ea49-40d2-93d6-35c4734263c3	ef797803-aaf9-4a7a-b7af-a86f6f010f9a	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	CommitteeDecision	93d8a260-c62c-4768-80e9-03056e8b0ed6	Decisioned	\N	system/AI	\N	{"resolution": "ApprovedWithConditions", "conditionsText": "Jordan Blake: Annual on-site audit of the vendor; PII encrypted at rest"}	\N	2026-09-25 07:23:38.508341+00
06305789-8686-4fd7-b5bd-a89a4a74c1fd	ef797803-aaf9-4a7a-b7af-a86f6f010f9a	\N	MockSystemsFeedback	ef797803-aaf9-4a7a-b7af-a86f6f010f9a	Pushed	\N	system	\N	{"goLive": true, "resolution": "ApprovedWithConditions", "ratingSummary": "Approved with conditions: Jordan Blake: Annual on-site audit of the vendor; PII encrypted at rest"}	\N	2026-09-25 07:23:38.691341+00
de3f37c3-02d1-466a-916d-52f6ff42b5f6	de00fb95-f4e9-4c55-9d17-781709873552	\N	ChangeRequest	de00fb95-f4e9-4c55-9d17-781709873552	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E FINAL09251251] API probe - config versioning", "status": "Submitted", "changeType": "CustomerSegment"}	\N	2026-09-25 07:23:47.43906+00
4df274b5-f1ce-4691-9e25-d513ee81feae	\N	\N	ScoringConfig	7a8c96fc-08c4-4f33-bcbc-ce10574ba2e0	ConfigChanged	374a3158-6dfa-41f2-9a4d-3d1091dffacf	human	\N	{"riskCategoryId": "22222222-2222-2222-2222-222222222222", "maxMitigationFactor": 0.8}	QA: in-flight isolation test (restored immediately)	2026-09-25 07:23:48.048137+00
7c06401d-5903-4702-a339-fb2f805a5beb	\N	416b67b7-55af-4246-b3e1-22ef35c2202a	RiskScore	2efc8859-1b96-4beb-85fc-a1ff7036ba88	Calculated	\N	system/AI	\N	{"inherent": 3, "residual": 2.200, "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	\N	2026-09-25 07:23:48.35413+00
0a82b61b-62fc-4b1e-b6cc-9e1c41dab045	\N	\N	ScoringConfig	2e831d36-94a8-4df9-96fd-a903a9326736	ConfigChanged	374a3158-6dfa-41f2-9a4d-3d1091dffacf	human	\N	{"riskCategoryId": "22222222-2222-2222-2222-222222222222", "maxMitigationFactor": 0.85}	QA: restore baseline after TC-API-102	2026-09-25 07:23:48.705612+00
571ea920-1da0-4339-bb7c-292c110ad999	\N	\N	WorkflowRule	a3000747-47f1-4f54-94ed-fc92a4f1ddbf	ConfigChanged	374a3158-6dfa-41f2-9a4d-3d1091dffacf	human	\N	{"ruleKey": "CommitteeQuorum", "ruleValue": {"quorum": 2}}	QA: re-save unchanged value	2026-09-25 07:23:51.481005+00
0777d3cc-ab75-43a7-bb5b-44e7abe9c75c	eee96cea-4f87-4d0d-95bd-565397ba8cea	\N	ChangeRequest	eee96cea-4f87-4d0d-95bd-565397ba8cea	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E FINAL09251251] API probe - actor spoofing", "status": "Submitted", "changeType": "Process"}	\N	2026-09-25 07:23:58.882002+00
d5efdc28-6fc8-4729-8c63-fa96543226a6	eee96cea-4f87-4d0d-95bd-565397ba8cea	7942e391-5a34-46ca-a3d7-6cbf46a5d164	Assessment	7942e391-5a34-46ca-a3d7-6cbf46a5d164	Finalized	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"finalizedBy": "a6a709a7-65e7-4a90-9b58-cbbaec1d651a"}	\N	2026-09-25 07:23:59.557587+00
57df451e-ef37-4e1b-8cda-33ff79cfdf31	\N	\N	ScoringConfig	afdc6f41-3e8d-469d-8242-f66632b86bd3	ConfigChanged	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"riskCategoryId": "22222222-2222-2222-2222-222222222222", "maxMitigationFactor": 0.85}	QA: RBAC probe - value unchanged	2026-09-25 07:23:59.835263+00
6241f81b-6c2c-434d-912b-71f89e1d37ba	0833e6e4-c347-4e8a-8be2-b3d3f722d1ab	\N	ChangeRequest	0833e6e4-c347-4e8a-8be2-b3d3f722d1ab	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E FINAL09251251] long AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", "status": "Submitted", "changeType": "Feature"}	\N	2026-09-25 07:24:15.21347+00
e385f78e-702f-47ec-af24-6f6d850ad1b7	507e6f32-ab80-40db-81bd-5f641ef033a4	\N	ChangeRequest	507e6f32-ab80-40db-81bd-5f641ef033a4	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E FINAL09251251] UI lifecycle - onboard Malta settlement vendor", "status": "Submitted", "changeType": "Vendor"}	\N	2026-09-25 07:25:29.009477+00
abe77c18-1253-4007-9bc3-257a4b2e9870	507e6f32-ab80-40db-81bd-5f641ef033a4	\N	ExternalSnapshot	507e6f32-ab80-40db-81bd-5f641ef033a4	Ingested	\N	system	\N	{"hasVendor": true, "hasProduct": false, "hasCustomer": false}	\N	2026-09-25 07:25:29.088453+00
5cce57d8-08f5-4cf9-9660-b0a80257f09e	507e6f32-ab80-40db-81bd-5f641ef033a4	\N	Attachment	00081c88-4365-4838-a6c0-96bc9b7b5258	Uploaded	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"version": 1, "fileName": "vendor-due-diligence.pdf"}	\N	2026-09-25 07:25:34.395694+00
278a1b92-44ee-46aa-9dce-84b1faac7f33	507e6f32-ab80-40db-81bd-5f641ef033a4	\N	Attachment	6dd3a474-8dce-4920-a29e-0f9f43cd72c7	Uploaded	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"version": 1, "fileName": "product-spec.docx"}	\N	2026-09-25 07:25:39.878335+00
3d1c40b8-e690-4802-93d0-51039a3951f9	\N	a46d7e97-e303-4945-bf55-5ff7405b2a25	CategoryMapping	62539f4f-631e-4767-b794-09075b9af826	AiProposed	\N	system/AI	\N	{"citation": "FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Customers", "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	\N	2026-09-25 07:26:28.419591+00
ecfd99e9-31e9-410a-9854-8e6f86a0ceb2	\N	a46d7e97-e303-4945-bf55-5ff7405b2a25	PolicyReliance	1c5e9549-f939-4833-b6b9-485611b34fd7	Decided	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"decision": "ReliedUpon", "policyChunkId": "e7a09ebd-9c1f-4779-8499-fa131c4a77c4"}	\N	2026-09-25 07:26:43.740565+00
f754fef7-59bd-4c72-a69d-916e399e4326	\N	a46d7e97-e303-4945-bf55-5ff7405b2a25	PolicyReliance	821b3477-5ac0-4edc-afea-bb3e8fdb2ea7	Decided	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"decision": "ReliedUpon", "policyChunkId": "539e307e-5d18-454b-a33c-fbcf3ff8c407"}	\N	2026-09-25 07:26:45.490252+00
45435889-8071-45db-a77c-0aefe5cda4cc	\N	a46d7e97-e303-4945-bf55-5ff7405b2a25	CategoryMapping	bdb8ac55-950b-42cf-9f9e-bbada977c064	AiProposed	\N	system/AI	\N	{"citation": "FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Products and Services (Delivery Channels)", "riskCategoryId": "22222222-2222-2222-2222-222222222224"}	\N	2026-09-25 07:26:28.460184+00
e6d5c3f0-234a-4b6b-94c4-56c1e198d8b5	\N	a46d7e97-e303-4945-bf55-5ff7405b2a25	CategoryMapping	9ea143f1-54a5-43ed-b020-a6fe379e1b96	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"isActive": true, "riskCategoryId": "22222222-2222-2222-2222-222222222223"}	Vendor domiciled in Malta - geographic exposure (QA)	2026-09-25 07:26:36.274804+00
4a5f7f6e-49d7-4df6-aec0-971db8b0d9d6	\N	a46d7e97-e303-4945-bf55-5ff7405b2a25	PolicyReliance	e7e1450c-4999-4099-8429-3890cb6ae16b	Decided	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"decision": "ReliedUpon", "policyChunkId": "79e625c1-e99c-43d0-9c93-4f2ee8b6f914"}	\N	2026-09-25 07:26:46.82065+00
2d9c928f-f88d-42f4-a20c-1282698565c1	507e6f32-ab80-40db-81bd-5f641ef033a4	\N	ExtractedField	0ca0fbe4-5920-4acd-b8d4-093d4af88538	AiExtracted	\N	system/AI	\N	{"value": "QuickPay Processing Ltd.", "fieldKey": "vendor_name", "confidence": 1, "needsReview": false}	\N	2026-09-25 07:27:11.26243+00
73904f9e-6e7c-4921-b13c-3257c7da855b	507e6f32-ab80-40db-81bd-5f641ef033a4	\N	ExtractedField	3964b793-9844-4c59-9555-d82628155a87	AiExtracted	\N	system/AI	\N	{"value": "Malta", "fieldKey": "vendor_jurisdiction", "confidence": 1, "needsReview": false}	\N	2026-09-25 07:27:11.29583+00
02ae8911-2716-4576-9840-b19ba5eef949	507e6f32-ab80-40db-81bd-5f641ef033a4	\N	ExtractedField	54b8f8c2-aee1-46a9-82e8-75b5ebe87481	AiExtracted	\N	system/AI	\N	{"value": "cardholder PII and settlement files", "fieldKey": "data_access_scope", "confidence": 1, "needsReview": false}	\N	2026-09-25 07:27:11.33312+00
e7778670-5da7-49c0-a0e6-95dd8f867362	\N	a46d7e97-e303-4945-bf55-5ff7405b2a25	NarrativeSection	4d76c74f-0c7c-425c-8ee9-02323e60af93	AiDrafted	\N	system/AI	\N	{"text": "The proposed business change involves onboarding QuickPay Processing Ltd, a vendor based in Malta, to serve as a card settlement processor. As part of this engagement, QuickPay Processing Ltd will receive sensitive cardholder personally identifiable information (PII) and settlement files via an API, necessitating rigorous oversight of the customer and entity risk associated with this arrangement. According to the FFIEC BSA/AML Manual, certain categories of customers and entities pose an elevated risk of money laundering, including those identified by geographic and sectoral risk factors (Risks Associated with Money Laundering and Terrorist Financing - Customers). Given QuickPay Processing Ltd's jurisdiction in Malta, it's imperative to factor in applicable country risk considerations as part of the risk-based customer due diligence program. \\n\\nThe bank's risk-based customer due diligence framework mandates scaling the level of scrutiny depending on the customer's risk profile. In this case, the collection of cardholder PII and settlement files expands the potential exposure to financial crime risks, necessitating commensurate due diligence measures on the vendor's anti-money laundering (AML) controls and legal/regulatory compliance in its operating jurisdiction. Although Malta is not explicitly cited within the policy excerpt as a higher-risk jurisdiction, geographic risk is a recognized factor in scaling due diligence scrutiny. Therefore, due diligence activities should focus on evaluating the vendor’s AML controls to mitigate potential money laundering and terrorist financing risks associated with the vendor relationship.", "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	\N	2026-09-25 07:27:44.278135+00
fd966aaf-f3a8-42d9-af7a-e31534644f61	\N	a46d7e97-e303-4945-bf55-5ff7405b2a25	NarrativeSection	90e2f3ba-fa19-4463-ab12-21ef4c7cf940	AiDrafted	\N	system/AI	\N	{"text": "The proposed business change involves onboarding QuickPay Processing Ltd., a Malta-based vendor, as a card settlement processor. The vendor will receive cardholder personally identifiable information (PII) and settlement files via an API. According to the FFIEC BSA/AML Manual section on Risks Associated with Money Laundering and Terrorist Financing regarding Delivery Channels, reliance on third-party agents and correspondent relationships to deliver products inherently increases risk due to the reduced ability of the bank to directly verify customer identity and intent. This reduction in direct verification capability necessitates a thorough risk assessment specific to the implications of using QuickPay Processing Ltd. as a settlement vendor.\\n\\nGiven that the vendor operates in a non-face-to-face, third-party capacity and will have access to sensitive cardholder data, it is critical that the bank's overall risk assessment explicitly addresses the risks introduced by the delivery channel change. This includes heightened consideration of identity validation challenges and potential vulnerabilities introduced by cross-jurisdictional operations with Malta. These risk factors must be carefully managed and mitigated in line with the guidance outlined in the FFIEC manual to ensure compliance and minimize exposure to financial crimes associated with delivery channels.", "riskCategoryId": "22222222-2222-2222-2222-222222222224"}	\N	2026-09-25 07:27:48.820611+00
7cab1e47-b079-43f9-bba1-30e8358662e9	\N	a46d7e97-e303-4945-bf55-5ff7405b2a25	NarrativeSection	59e9ae44-77fb-4de3-9817-f8d0149bdaec	AiDrafted	\N	system/AI	\N	{"text": "The proposed onboarding of QuickPay Processing Ltd, a vendor based in Malta, as a card settlement processor introduces geographic risk considerations as delineated in the FFIEC BSA/AML Manual. Geographic risk assessment focuses on exposure to jurisdictions identified by FATF for strategic AML/CFT deficiencies, jurisdictions under OFAC sanctions, and domestic High Intensity Financial Crime Areas (HIFCAs). While Malta is the vendor’s jurisdiction, it is essential to evaluate its standing relative to these critical risk indicators to determine the appropriate level of scrutiny. The vendor will handle sensitive cardholder personally identifiable information (PII) and settlement files via API, which heightens the importance of assessing the AML/CFT risks associated with their geographic location. Given that the policy mandates additional scrutiny for products, customers, and transactions connected to higher-risk jurisdictions, this vendor relationship warrants a thorough due diligence process to identify and mitigate such risks effectively (Risks Associated with Money Laundering and Terrorist Financing - Geographic Locations).", "riskCategoryId": "22222222-2222-2222-2222-222222222223"}	\N	2026-09-25 07:27:52.432998+00
1f200f65-3394-476e-b565-204cf88d81d9	\N	a46d7e97-e303-4945-bf55-5ff7405b2a25	NarrativeSection	90e2f3ba-fa19-4463-ab12-21ef4c7cf940	AnalystReviewed	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"status": "AnalystReviewed", "riskCategoryId": "22222222-2222-2222-2222-222222222224"}	\N	2026-09-25 07:28:07.53501+00
70abe96b-cf48-42d2-aab7-0fbe65ecaf9b	\N	a46d7e97-e303-4945-bf55-5ff7405b2a25	RiskScore	0cb580e5-2551-45c2-9b2f-7303b60ed4b6	Calculated	\N	system/AI	\N	{"inherent": 3, "residual": 2.5750, "riskCategoryId": "22222222-2222-2222-2222-222222222224"}	\N	2026-09-25 07:28:16.907935+00
80318f78-6ccc-4bb7-8134-0c905e70e0cb	\N	a46d7e97-e303-4945-bf55-5ff7405b2a25	RiskScore	c5f1159c-e715-4f4c-af85-04f4819fe3eb	Calculated	\N	system/AI	\N	{"inherent": 3, "residual": 2.5750, "riskCategoryId": "22222222-2222-2222-2222-222222222223"}	\N	2026-09-25 07:28:17.537736+00
90aada9f-29ed-4759-85fb-cd72a460ba74	507e6f32-ab80-40db-81bd-5f641ef033a4	a46d7e97-e303-4945-bf55-5ff7405b2a25	Assessment	a46d7e97-e303-4945-bf55-5ff7405b2a25	Finalized	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"finalizedBy": "4fa322d3-2245-44ef-b664-1a804442db23"}	\N	2026-09-25 07:28:40.58401+00
419ac6f3-9941-4f70-a2f4-456b3f910e0b	507e6f32-ab80-40db-81bd-5f641ef033a4	a46d7e97-e303-4945-bf55-5ff7405b2a25	ChangeRequest	507e6f32-ab80-40db-81bd-5f641ef033a4	Routed	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"status": "PendingCommittee"}	\N	2026-09-25 07:28:41.483859+00
eebfce51-5ffd-4e9b-b574-d2204bfd2868	507e6f32-ab80-40db-81bd-5f641ef033a4	a46d7e97-e303-4945-bf55-5ff7405b2a25	CommitteeVote	47318d69-c173-4a44-bb87-8db325761c58	Voted	083ecfe5-aa01-4703-9168-762f0065078f	human	\N	{"vote": "ApproveWithConditions", "rationale": null, "conditionsText": "Annual on-site audit of the vendor; cardholder PII encrypted at rest (QA)"}	\N	2026-09-25 07:29:18.301734+00
dc43bb49-9dd2-49f3-9bb4-6474ac24bbea	507e6f32-ab80-40db-81bd-5f641ef033a4	a46d7e97-e303-4945-bf55-5ff7405b2a25	CommitteeVote	97c03a80-5032-4fe0-9aaf-a73c367df959	Voted	fa142c1c-58cc-4666-b135-7768a2ab33f0	human	\N	{"vote": "Approve", "rationale": null, "conditionsText": null}	\N	2026-09-25 07:29:26.315845+00
3fe32b6b-cfbe-4af5-be21-b14900f373cd	\N	a46d7e97-e303-4945-bf55-5ff7405b2a25	NarrativeSection	4d76c74f-0c7c-425c-8ee9-02323e60af93	AnalystEdited	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "4d76c74f-0c7c-425c-8ee9-02323e60af93", "status": "AiDrafted", "updated_at": "2026-09-25T07:27:44.278135+00:00", "assessment_id": "a46d7e97-e303-4945-bf55-5ff7405b2a25", "narrative_text": "The proposed business change involves onboarding QuickPay Processing Ltd, a vendor based in Malta, to serve as a card settlement processor. As part of this engagement, QuickPay Processing Ltd will receive sensitive cardholder personally identifiable information (PII) and settlement files via an API, necessitating rigorous oversight of the customer and entity risk associated with this arrangement. According to the FFIEC BSA/AML Manual, certain categories of customers and entities pose an elevated risk of money laundering, including those identified by geographic and sectoral risk factors (Risks Associated with Money Laundering and Terrorist Financing - Customers). Given QuickPay Processing Ltd's jurisdiction in Malta, it's imperative to factor in applicable country risk considerations as part of the risk-based customer due diligence program. \\n\\nThe bank's risk-based customer due diligence framework mandates scaling the level of scrutiny depending on the customer's risk profile. In this case, the collection of cardholder PII and settlement files expands the potential exposure to financial crime risks, necessitating commensurate due diligence measures on the vendor's anti-money laundering (AML) controls and legal/regulatory compliance in its operating jurisdiction. Although Malta is not explicitly cited within the policy excerpt as a higher-risk jurisdiction, geographic risk is a recognized factor in scaling due diligence scrutiny. Therefore, due diligence activities should focus on evaluating the vendor’s AML controls to mitigate potential money laundering and terrorist financing risks associated with the vendor relationship.", "risk_category_id": "22222222-2222-2222-2222-222222222222", "updated_by_user_id": null, "unsupported_claim_flags": ["Malta is considered a higher-risk jurisdiction necessitating enhanced due diligence", "QuickPay Processing Ltd's AML controls have been evaluated and deemed sufficient"]}	{"text": "QA analyst narrative: onboarding a Malta-domiciled settlement processor with API access to cardholder PII. EDD and annual audit rights required.", "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	Added EDD requirement and tightened wording (QA)	2026-09-25 07:28:06.472729+00
586c4412-59eb-4b9f-9190-f0448f0eae70	\N	a46d7e97-e303-4945-bf55-5ff7405b2a25	NarrativeSection	59e9ae44-77fb-4de3-9817-f8d0149bdaec	AnalystReviewed	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"status": "AnalystReviewed", "riskCategoryId": "22222222-2222-2222-2222-222222222223"}	\N	2026-09-25 07:28:08.582623+00
ecf2aa17-965a-4151-820c-4a5660ce3de6	\N	a46d7e97-e303-4945-bf55-5ff7405b2a25	RiskScore	dcd47fb3-16a0-47e9-9074-cf8abbe1735d	Calculated	\N	system/AI	\N	{"inherent": 5, "residual": 4.150, "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	\N	2026-09-25 07:28:15.762956+00
041c4cfe-c696-4c57-ae0b-ff7d82ef2bbd	\N	a46d7e97-e303-4945-bf55-5ff7405b2a25	RiskScore	dcd47fb3-16a0-47e9-9074-cf8abbe1735d	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "dcd47fb3-16a0-47e9-9074-cf8abbe1735d", "scored_by": "System", "created_at": "2026-09-25T07:28:15.762956+00:00", "is_override": false, "assessment_id": "a46d7e97-e303-4945-bf55-5ff7405b2a25", "inherent_rating": 5.00, "override_reason": null, "residual_rating": 4.15, "risk_category_id": "22222222-2222-2222-2222-222222222222", "created_by_user_id": null, "control_ids_credited": [], "control_effectiveness": 1.000, "mitigation_factor_applied": 0.850}	{"residual": 2.5, "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	Vendor had prior regulatory findings (QA)	2026-09-25 07:28:33.946054+00
f09a8bf0-633c-45be-9128-9a188dff68b5	507e6f32-ab80-40db-81bd-5f641ef033a4	a46d7e97-e303-4945-bf55-5ff7405b2a25	CommitteeDecision	9872b5b1-8173-4994-bd4e-015db347b5c2	Decisioned	\N	system/AI	\N	{"resolution": "ApprovedWithConditions", "conditionsText": "Jordan Blake: Annual on-site audit of the vendor; cardholder PII encrypted at rest (QA)"}	\N	2026-09-25 07:29:26.454241+00
e6051824-c717-41c4-86dd-2800c7d69210	507e6f32-ab80-40db-81bd-5f641ef033a4	\N	MockSystemsFeedback	507e6f32-ab80-40db-81bd-5f641ef033a4	Pushed	\N	system	\N	{"goLive": true, "resolution": "ApprovedWithConditions", "ratingSummary": "Approved with conditions: Jordan Blake: Annual on-site audit of the vendor; cardholder PII encrypted at rest (QA)"}	\N	2026-09-25 07:29:26.909878+00
b36c8e69-c70b-4df6-b5c2-8ba6a3d849f8	\N	\N	ScoringConfig	e541d012-e837-480a-9184-c5b8c221d406	ConfigChanged	374a3158-6dfa-41f2-9a4d-3d1091dffacf	human	\N	{"riskCategoryId": "22222222-2222-2222-2222-222222222222", "maxMitigationFactor": 0.85}	QA: re-save unchanged baseline	2026-09-25 07:29:52.785235+00
0c6a9fbe-cd3d-4148-a8f2-49babc8ea80a	95c5cf1d-f648-489c-8391-20721104947f	\N	ChangeRequest	95c5cf1d-f648-489c-8391-20721104947f	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E FINAL09251251] <img src=x onerror=\\"window.__xss=1\\"><script>window.__xss=2</script>", "status": "Submitted", "changeType": "Feature"}	\N	2026-09-25 07:29:55.042837+00
a3002a28-a9f6-4173-a96c-da4c3d47dfec	507e6f32-ab80-40db-81bd-5f641ef033a4	\N	ExtractedField	0ca0fbe4-5920-4acd-b8d4-093d4af88538	AiExtracted	\N	system/AI	\N	{"value": "QuickPay Processing Ltd.", "fieldKey": "vendor_name", "confidence": 1, "needsReview": false}	\N	2026-09-25 07:34:08.71853+00
9a64f044-5e78-4570-8eef-821f8bb49828	507e6f32-ab80-40db-81bd-5f641ef033a4	\N	ExtractedField	3964b793-9844-4c59-9555-d82628155a87	AiExtracted	\N	system/AI	\N	{"value": "Malta", "fieldKey": "vendor_jurisdiction", "confidence": 1, "needsReview": false}	\N	2026-09-25 07:34:08.757853+00
5d17563e-2951-4cf0-b245-af4c27b3a30c	507e6f32-ab80-40db-81bd-5f641ef033a4	\N	ExtractedField	54b8f8c2-aee1-46a9-82e8-75b5ebe87481	AiExtracted	\N	system/AI	\N	{"value": "cardholder PII and settlement files", "fieldKey": "data_access_scope", "confidence": 1, "needsReview": false}	\N	2026-09-25 07:34:08.792632+00
bd8aa78a-98a7-4efd-9640-7c6c9bc9c68c	2f3859fc-cf3f-44fe-88d3-9ab40b8585e4	\N	ChangeRequest	2f3859fc-cf3f-44fe-88d3-9ab40b8585e4	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609280759] API intake - prepaid card", "status": "Submitted", "changeType": "Product"}	\N	2026-09-28 08:00:05.779798+00
54100584-0d10-4818-86f2-3e8597aa6d72	2f3859fc-cf3f-44fe-88d3-9ab40b8585e4	\N	ExternalSnapshot	2f3859fc-cf3f-44fe-88d3-9ab40b8585e4	Ingested	\N	system	\N	{"hasVendor": false, "hasProduct": true, "hasCustomer": false}	\N	2026-09-28 08:00:05.894158+00
d4cd298b-b2d8-4896-8155-2b853735db2c	55d227e6-ab38-4a7b-b2b2-271a6482b96b	\N	ChangeRequest	55d227e6-ab38-4a7b-b2b2-271a6482b96b	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609280759] type Product", "status": "Submitted", "changeType": "Product"}	\N	2026-09-28 08:00:07.287832+00
eacd33d5-7e61-4312-b2b7-7fdf2de061ff	4fd54ca9-b073-4733-94a5-4ab3e7b61c01	\N	ChangeRequest	4fd54ca9-b073-4733-94a5-4ab3e7b61c01	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609280759] type Feature", "status": "Submitted", "changeType": "Feature"}	\N	2026-09-28 08:00:07.65264+00
36c3c791-d583-421e-b835-fa07d4612cf1	89c78436-ebd6-41fc-bdc0-0c7c9807d8b8	\N	ChangeRequest	89c78436-ebd6-41fc-bdc0-0c7c9807d8b8	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609280759] type Process", "status": "Submitted", "changeType": "Process"}	\N	2026-09-28 08:00:07.989647+00
90260c7b-0c76-45d1-b2df-ad040d9d150b	0a731172-0bbb-4489-aec4-db7828dd5928	\N	ChangeRequest	0a731172-0bbb-4489-aec4-db7828dd5928	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609280759] type Vendor", "status": "Submitted", "changeType": "Vendor"}	\N	2026-09-28 08:00:08.327834+00
a1fc4202-1201-4092-9f88-5994a8b3bc46	cc995f7a-83e3-493f-b12c-ab0f43097f3a	\N	ChangeRequest	cc995f7a-83e3-493f-b12c-ab0f43097f3a	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609280759] type Geography", "status": "Submitted", "changeType": "Geography"}	\N	2026-09-28 08:00:08.659638+00
a1f3259a-45fc-4195-b7cb-2df52274b15d	bea75b32-b4c1-45d7-8ec9-65598745cf4e	\N	ChangeRequest	bea75b32-b4c1-45d7-8ec9-65598745cf4e	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609280759] type CustomerSegment", "status": "Submitted", "changeType": "CustomerSegment"}	\N	2026-09-28 08:00:08.986344+00
99b96d2a-a863-4aa5-a045-1350ef2bcca5	e61cc526-3149-4f64-ac51-03cf2d2612f6	\N	ChangeRequest	e61cc526-3149-4f64-ac51-03cf2d2612f6	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "", "status": "Submitted", "changeType": "Product"}	\N	2026-09-28 08:00:11.419736+00
d092ff2a-60c0-4d23-af78-4824cfe2b6ad	a9d2beb0-3e2b-4931-bced-0f79150dac20	\N	ChangeRequest	a9d2beb0-3e2b-4931-bced-0f79150dac20	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609280759] attachments", "status": "Submitted", "changeType": "Vendor"}	\N	2026-09-28 08:00:21.218879+00
8b384147-d11b-444c-9973-76687e79ac21	a9d2beb0-3e2b-4931-bced-0f79150dac20	\N	Attachment	5ea19f44-100e-4c9f-8c13-716e8caf0afa	Uploaded	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"version": 1, "fileName": "vendor-due-diligence.pdf"}	\N	2026-09-28 08:00:22.525538+00
ae4c9282-e56c-4fcd-91ba-a5e9f63f3963	a9d2beb0-3e2b-4931-bced-0f79150dac20	\N	Attachment	ea0c926c-5aa4-4d8d-ae76-97d8d19427da	Uploaded	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"version": 1, "fileName": "product-spec.docx"}	\N	2026-09-28 08:00:22.870235+00
daa647d3-5563-4996-ac67-abefc4855b69	a9d2beb0-3e2b-4931-bced-0f79150dac20	\N	Attachment	3e2f310e-760d-4b58-9865-638b0e77c329	Uploaded	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"version": 1, "fileName": "control-matrix.xlsx"}	\N	2026-09-28 08:00:23.217589+00
6dc9a901-8387-413a-897a-d2d66e1fd360	11f899a8-e66a-4572-915e-b077ecf43280	\N	ChangeRequest	11f899a8-e66a-4572-915e-b077ecf43280	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609280759] bad uploads", "status": "Submitted", "changeType": "Vendor"}	\N	2026-09-28 08:00:26.619129+00
71b299a7-2ac4-4cfe-84e0-81d3dfa0c5d4	11f899a8-e66a-4572-915e-b077ecf43280	\N	Attachment	f5d18095-5bf1-4eb0-9f1c-acf363fd2c69	Uploaded	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"version": 1, "fileName": "malicious.exe"}	\N	2026-09-28 08:00:27.441842+00
6b304327-0d66-4032-8c25-a8a9c70724c9	62d2e0eb-c313-408c-b0b1-70ffe1196565	\N	ChangeRequest	62d2e0eb-c313-408c-b0b1-70ffe1196565	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609280759] clarification", "status": "Submitted", "changeType": "Geography"}	\N	2026-09-28 08:00:29.977655+00
2189980c-3213-454a-af5e-07ebd78f1a7a	62d2e0eb-c313-408c-b0b1-70ffe1196565	\N	Clarification	04632043-f561-43f6-98b4-6ea2b4b73fea	Requested	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"question": "Which target countries exactly?"}	\N	2026-09-28 08:00:30.294633+00
d441d1d7-f0ff-4097-bec7-2d1e28210683	8dce6573-54e9-41c3-a3f0-9b615351582d	\N	ChangeRequest	8dce6573-54e9-41c3-a3f0-9b615351582d	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609280759] snapshot linked", "status": "Submitted", "changeType": "Product"}	\N	2026-09-28 08:00:31.521582+00
e2df5a0c-5039-42df-bf01-c53b100d6a73	8dce6573-54e9-41c3-a3f0-9b615351582d	\N	ExternalSnapshot	8dce6573-54e9-41c3-a3f0-9b615351582d	Ingested	\N	system	\N	{"hasVendor": false, "hasProduct": true, "hasCustomer": false}	\N	2026-09-28 08:00:31.606928+00
fa45b3eb-5296-4e82-a20d-b7561ca12d1b	7f4b8f70-f2cc-4aca-890a-876a16f9860a	\N	ChangeRequest	7f4b8f70-f2cc-4aca-890a-876a16f9860a	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609280759] snapshot none", "status": "Submitted", "changeType": "Process"}	\N	2026-09-28 08:00:31.903104+00
2f4a3cdf-bb8f-424b-9558-db18a89d228e	617f16d3-e50b-487c-a31d-cedbbc7b572a	\N	ChangeRequest	617f16d3-e50b-487c-a31d-cedbbc7b572a	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609280759] API lifecycle - onboard settlement vendor", "status": "Submitted", "changeType": "Vendor"}	\N	2026-09-28 08:00:33.744622+00
0b857b3f-745a-4aaa-84c0-2e184c6498f0	617f16d3-e50b-487c-a31d-cedbbc7b572a	\N	ExternalSnapshot	617f16d3-e50b-487c-a31d-cedbbc7b572a	Ingested	\N	system	\N	{"hasVendor": true, "hasProduct": false, "hasCustomer": false}	\N	2026-09-28 08:00:33.834771+00
f6850e02-aefe-4814-b2ee-f49db9353511	617f16d3-e50b-487c-a31d-cedbbc7b572a	\N	Attachment	d9da15e7-6334-4e80-8024-90c0234ef226	Uploaded	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"version": 1, "fileName": "vendor-due-diligence.pdf"}	\N	2026-09-28 08:00:34.174284+00
7f498438-cd51-44a1-9948-9019230a5f60	540ffca2-0e67-4ed9-9e72-39e1aa12152d	\N	ChangeRequest	540ffca2-0e67-4ed9-9e72-39e1aa12152d	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609280759] API probe - empty assessment", "status": "Submitted", "changeType": "Feature"}	\N	2026-09-28 08:00:35.897563+00
a9609f29-d5c9-4c25-b4aa-4eb7680b0716	540ffca2-0e67-4ed9-9e72-39e1aa12152d	90b8631a-dba0-43a1-b722-92176fd4bd13	Assessment	90b8631a-dba0-43a1-b722-92176fd4bd13	Finalized	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"finalizedBy": "4fa322d3-2245-44ef-b664-1a804442db23"}	\N	2026-09-28 08:00:36.902328+00
e14f1c8b-e868-4c69-adf0-5489e918c55c	540ffca2-0e67-4ed9-9e72-39e1aa12152d	90b8631a-dba0-43a1-b722-92176fd4bd13	ChangeRequest	540ffca2-0e67-4ed9-9e72-39e1aa12152d	Routed	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"status": "PendingCommittee"}	\N	2026-09-28 08:00:37.181242+00
fc5f8f3d-10ae-4f34-a273-6c439dd1a9f9	\N	9534f3f0-685a-4450-bfc0-983f2d16f7d9	CategoryMapping	0059904e-b067-4a97-b45b-064e2919712e	AiProposed	\N	system/AI	\N	{"citation": "FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Customers", "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	\N	2026-09-28 08:00:42.461151+00
06f3e3d1-fe79-4b93-a200-c713bc3d8fbc	\N	9534f3f0-685a-4450-bfc0-983f2d16f7d9	CategoryMapping	79abf61f-67ac-4f8f-97e2-2da55aa55af7	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"isActive": true, "riskCategoryId": "22222222-2222-2222-2222-222222222223"}	Vendor is domiciled in Malta - geographic exposure	2026-09-28 08:00:46.500875+00
783479ba-6612-4031-807a-cee99ca95f60	\N	9534f3f0-685a-4450-bfc0-983f2d16f7d9	CategoryMapping	31c31263-0172-4071-961c-486097d2d728	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"isActive": false, "riskCategoryId": "22222222-2222-2222-2222-222222222224"}	QA: removal test	2026-09-28 08:00:46.801393+00
a3829d21-1eab-4900-a9b7-d4e4ad52512f	\N	fe6f95b7-3a35-4799-9eb2-e3239a6a3674	CategoryMapping	d4ecc71e-6db1-4389-b0ac-fa4c09f2b2ca	AiProposed	\N	system/AI	\N	{"citation": "FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Customers", "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	\N	2026-09-28 08:05:27.540723+00
e9580662-1684-4c71-b50b-e73ac4aa93d9	\N	9534f3f0-685a-4450-bfc0-983f2d16f7d9	CategoryMapping	31c31263-0172-4071-961c-486097d2d728	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "31c31263-0172-4071-961c-486097d2d728", "source": "AnalystAdded", "is_active": false, "created_at": "2026-09-28T08:00:46.801393+00:00", "ai_citation": null, "assessment_id": "9534f3f0-685a-4450-bfc0-983f2d16f7d9", "risk_category_id": "22222222-2222-2222-2222-222222222224", "created_by_user_id": "4fa322d3-2245-44ef-b664-1a804442db23"}	{"isActive": true, "riskCategoryId": "22222222-2222-2222-2222-222222222224"}	QA: restore - API channel is non-face-to-face	2026-09-28 08:00:47.100526+00
c5024fbb-6049-4d54-85e9-5a073e718cc5	\N	9534f3f0-685a-4450-bfc0-983f2d16f7d9	PolicyReliance	766fd40e-fbcb-45d9-9689-de5052f9ade6	Decided	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"decision": "ReliedUpon", "policyChunkId": "3f171e93-f2ca-40a4-af6a-18ede9021c9b"}	\N	2026-09-28 08:00:56.714166+00
f100beff-2a1b-4944-8ca5-134f3f0f236d	\N	9534f3f0-685a-4450-bfc0-983f2d16f7d9	PolicyReliance	06688e6b-73bb-4eda-beda-40dbce2d26d1	Decided	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"decision": "ReliedUpon", "policyChunkId": "539e307e-5d18-454b-a33c-fbcf3ff8c407"}	\N	2026-09-28 08:00:57.025116+00
6ee7f800-6b58-4f7f-9928-6f019ecd3b35	\N	9534f3f0-685a-4450-bfc0-983f2d16f7d9	PolicyReliance	6d748489-b0ba-4211-bfd5-911b2365069b	Decided	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"decision": "ReliedUpon", "policyChunkId": "8fc9b915-62af-410e-af73-373e51aac522"}	\N	2026-09-28 08:00:57.337258+00
d1ba2cb2-0895-4af5-8482-2936e10fc49d	\N	9534f3f0-685a-4450-bfc0-983f2d16f7d9	PolicyReliance	6422fce4-2023-41e4-9c57-ad839bcc0218	Decided	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"decision": "NotRelevant", "policyChunkId": "af07f40f-b9fa-4614-891b-b0fcc9a8f54b"}	\N	2026-09-28 08:00:57.645695+00
a754959f-6150-4383-9576-2dc4ef8975c6	\N	90b8631a-dba0-43a1-b722-92176fd4bd13	PolicyReliance	71b44dfc-dbfe-4cea-97ca-fe0d72a1ace0	Decided	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"decision": "ReliedUpon", "policyChunkId": "3f171e93-f2ca-40a4-af6a-18ede9021c9b"}	\N	2026-09-28 08:01:00.623334+00
7922e4a9-3cd5-41ba-ad01-6cef5c21a8f0	\N	90b8631a-dba0-43a1-b722-92176fd4bd13	PolicyReliance	71b44dfc-dbfe-4cea-97ca-fe0d72a1ace0	Decided	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"decision": "ReliedUpon", "policyChunkId": "3f171e93-f2ca-40a4-af6a-18ede9021c9b"}	\N	2026-09-28 08:01:00.922567+00
2462da23-010f-4112-9679-9d36606b11ee	617f16d3-e50b-487c-a31d-cedbbc7b572a	\N	ExtractedField	d079bc02-c970-4eda-aed6-56f3f94f0bec	AiExtracted	\N	system/AI	\N	{"value": "QuickPay Processing Ltd", "fieldKey": "vendor_name", "confidence": 1, "needsReview": false}	\N	2026-09-28 08:01:07.288522+00
ad5e2853-0719-435e-ac4f-5add3ffae47e	617f16d3-e50b-487c-a31d-cedbbc7b572a	\N	ExtractedField	e3d69ed2-16fa-41c0-82e7-12aa97bc8f03	AiExtracted	\N	system/AI	\N	{"value": "Malta", "fieldKey": "vendor_jurisdiction", "confidence": 1, "needsReview": false}	\N	2026-09-28 08:01:07.330827+00
b7d51264-a705-4017-b41c-d90901ca4d31	617f16d3-e50b-487c-a31d-cedbbc7b572a	\N	ExtractedField	20244ea1-a869-4344-8084-8be6bdaa40c8	AiExtracted	\N	system/AI	\N	{"value": "cardholder PII and settlement files", "fieldKey": "data_access_scope", "confidence": 1, "needsReview": false}	\N	2026-09-28 08:01:07.369108+00
bfa6a031-0ff7-457a-b615-c51633fb9dd2	617f16d3-e50b-487c-a31d-cedbbc7b572a	\N	ExtractedField	e207ff50-94da-4604-a04c-f9ba7dc3ec8c	AiExtracted	\N	system/AI	\N	{"value": "retail cardholders, MSB merchants", "fieldKey": "customer_types_affected", "confidence": 1, "needsReview": false}	\N	2026-09-28 08:01:07.407122+00
d7140009-3bfd-4668-bb98-edfe8d86fc45	617f16d3-e50b-487c-a31d-cedbbc7b572a	\N	ExtractedField	41f2319d-4ef4-4e93-bfe4-d477daae46a3	AiExtracted	\N	system/AI	\N	{"value": "API, non-face-to-face", "fieldKey": "delivery_channel", "confidence": 1, "needsReview": false}	\N	2026-09-28 08:01:07.450071+00
eb4c6469-2204-409d-98b4-56d88f029a03	617f16d3-e50b-487c-a31d-cedbbc7b572a	\N	ExtractedField	d079bc02-c970-4eda-aed6-56f3f94f0bec	Corrected	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "d079bc02-c970-4eda-aed6-56f3f94f0bec", "source": "AiExtracted", "field_key": "vendor_name", "confidence": 1.000, "updated_at": "2026-09-28T08:01:07.288522+00:00", "field_value": "QuickPay Processing Ltd", "needs_review": false, "attachment_id": "d9da15e7-6334-4e80-8024-90c0234ef226", "source_excerpt": "Vendor name: QuickPay Processing Ltd", "change_request_id": "617f16d3-e50b-487c-a31d-cedbbc7b572a", "updated_by_user_id": null}	{"value": "QA value ", "fieldKey": "vendor_name"}	\N	2026-09-28 08:01:08.86436+00
c61168d4-8385-49bd-b250-dc02b438cc14	617f16d3-e50b-487c-a31d-cedbbc7b572a	\N	ExtractedField	d079bc02-c970-4eda-aed6-56f3f94f0bec	Corrected	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "d079bc02-c970-4eda-aed6-56f3f94f0bec", "source": "AnalystCorrected", "field_key": "vendor_name", "confidence": null, "updated_at": "2026-09-28T08:01:08.86436+00:00", "field_value": "QA value ", "needs_review": false, "attachment_id": "d9da15e7-6334-4e80-8024-90c0234ef226", "source_excerpt": "Vendor name: QuickPay Processing Ltd", "change_request_id": "617f16d3-e50b-487c-a31d-cedbbc7b572a", "updated_by_user_id": "4fa322d3-2245-44ef-b664-1a804442db23"}	{"value": "QA corrected value", "fieldKey": "vendor_name"}	Contract section 4 states otherwise	2026-09-28 08:01:09.158672+00
c83ba99a-51b8-4e1f-9882-b7b93ca2ce95	\N	9534f3f0-685a-4450-bfc0-983f2d16f7d9	NarrativeSection	fe5cfe98-0efc-4524-a1db-1aabb69d89b4	AiDrafted	\N	system/AI	\N	{"text": "The proposed business change involves onboarding a Malta-based vendor, QA corrected value, as a card settlement processor with access to cardholder Personally Identifiable Information (PII) and settlement files. This vendor will process transactions primarily for retail cardholders and Money Services Business (MSB) merchants. The delivery channel for the vendor's services will be via an API, which constitutes a non-face-to-face interaction channel. \\n\\nAccording to the FFIEC BSA/AML Manual section on Risks Associated with Money Laundering and Terrorist Financing: Customers, certain products and services, such as those involving electronic funds transfers and limited face-to-face contact, are inherently vulnerable to money laundering risks. The non-face-to-face nature of the API delivery channel aligns with this identified risk due to limited direct customer interaction. The involvement of cardholder PII further elevates the risk profile given the sensitivity of the data accessed by the vendor. \\n\\nIt is therefore critical that the bank has identified, measured, and mitigated the risks posed by onboarding this vendor, especially concerning the protection of PII and the oversight of transaction processing for retail cardholders and MSB merchants through electronic means. Ensuring robust controls and ongoing monitoring consistent with the bank's risk management framework will be essential to address the inherent vulnerabilities highlighted in the supervisory guidance.", "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	\N	2026-09-28 08:01:14.669485+00
8cb58d2b-88e1-4b9a-a760-167dc2cc4495	\N	9534f3f0-685a-4450-bfc0-983f2d16f7d9	RiskScore	084b8a1f-26d9-4a7a-a0f8-f8b0dd964f87	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "084b8a1f-26d9-4a7a-a0f8-f8b0dd964f87", "scored_by": "System", "created_at": "2026-09-28T08:01:33.976207+00:00", "is_override": false, "assessment_id": "9534f3f0-685a-4450-bfc0-983f2d16f7d9", "inherent_rating": 4.00, "override_reason": null, "residual_rating": 3.32, "risk_category_id": "22222222-2222-2222-2222-222222222222", "created_by_user_id": null, "control_ids_credited": [], "control_effectiveness": 0.800, "mitigation_factor_applied": 0.850}	{"residual": 2.5, "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	Vendor has had two prior regulatory findings	2026-09-28 08:01:40.013366+00
74a46f77-c1b7-4d0a-b914-0665739039ff	617f16d3-e50b-487c-a31d-cedbbc7b572a	9534f3f0-685a-4450-bfc0-983f2d16f7d9	Assessment	9534f3f0-685a-4450-bfc0-983f2d16f7d9	Finalized	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"finalizedBy": "4fa322d3-2245-44ef-b664-1a804442db23"}	\N	2026-09-28 08:01:47.92983+00
48280f7b-1339-4503-ad36-5635c2ac3d89	617f16d3-e50b-487c-a31d-cedbbc7b572a	9534f3f0-685a-4450-bfc0-983f2d16f7d9	ChangeRequest	617f16d3-e50b-487c-a31d-cedbbc7b572a	Routed	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"status": "PendingCommittee"}	\N	2026-09-28 08:01:48.252891+00
99f55a8d-d7e6-46da-8f9c-93adb50c1f4e	\N	fe6f95b7-3a35-4799-9eb2-e3239a6a3674	CategoryMapping	c31d1ada-e59a-4691-be12-9b081a7c1772	AiProposed	\N	system/AI	\N	{"citation": "FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Products and Services (Delivery Channels)", "riskCategoryId": "22222222-2222-2222-2222-222222222224"}	\N	2026-09-28 08:05:27.580263+00
24be5159-dbb5-42b9-977a-124dc7d3659c	\N	fe6f95b7-3a35-4799-9eb2-e3239a6a3674	CategoryMapping	a2e1b5c8-9a54-42a3-8019-9e2739446cc3	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"isActive": true, "riskCategoryId": "22222222-2222-2222-2222-222222222223"}	Vendor domiciled in Malta - geographic exposure (QA)	2026-09-28 08:05:34.266294+00
bf58ec26-9f9a-4e64-a6b4-e66dba1d1736	\N	9534f3f0-685a-4450-bfc0-983f2d16f7d9	NarrativeSection	0338c9b2-a2a5-4004-a183-f3d02286bb56	AiDrafted	\N	system/AI	\N	{"text": "The proposed business change to onboard QA corrected value, a Malta-based card settlement vendor, introduces specific geographic risk considerations as outlined in the FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing. Malta, as the vendor's jurisdiction, presents inherent country-specific risks that must be evaluated due to potential vulnerabilities related to money laundering and terrorist financing in certain geographic locations. The access granted to the vendor includes cardholder personally identifiable information (PII) and settlement files, heightening the sensitivity of data involved.\\n\\nGiven that the delivery channel for this vendor's services is via an API, which is a non-face-to-face transaction channel, the concerns noted in the policy about reduced ability to verify customer identity and intent directly are applicable here. Reliance on such third-party arrangements through non-face-to-face channels amplifies the risk profile and should be thoroughly factored into the overall risk assessment of this change (Risks Associated with Money Laundering and Terrorist Financing - Delivery Channels). The impacted customer types encompass retail cardholders and money services business (MSB) merchants, emphasizing the need for diligent risk controls to mitigate exposure related to these groups.\\n\\nIn summary, the onboarding of this Malta-based vendor with API-based non-face-to-face access to sensitive cardholder and transaction data necessitates a comprehensive evaluation of geographic risks as well as the delivery channel risks described in the cited FFIEC manual excerpt. These factors must be integrated into the FCRM assessment to ensure appropriate monitoring and mitigation strategies are established.", "riskCategoryId": "22222222-2222-2222-2222-222222222223"}	\N	2026-09-28 08:01:19.680069+00
314bf1e0-13bb-4aab-8934-3b84a3cf89c1	\N	9534f3f0-685a-4450-bfc0-983f2d16f7d9	NarrativeSection	59d6e75a-6bb2-4339-b408-3c2ab91119cf	AiDrafted	\N	system/AI	\N	{"text": "The proposed business change involves onboarding QA corrected value, a Malta-based card settlement processor, which will have access to cardholder personally identifiable information (PII) and settlement files through an API-based delivery channel. This constitutes a non-face-to-face electronic channel, which inherently carries heightened risks for money laundering and terrorist financing due to potential limitations in customer interaction and identification verification processes. Given the vendor's jurisdiction in Malta, the bank must consider country-specific risks as part of an enhanced due diligence process, consistent with expectations for correspondent relationships involving higher-risk jurisdictions, as outlined in the FFIEC BSA/AML Manual (Risks Associated with Money Laundering and Terrorist Financing - Correspondent Banking). Although the vendor is not a correspondent bank, parallel scrutiny is warranted because of the sensitive data access and the involvement in settlement processing that interfaces with the bank's retail cardholders and money services business (MSB) merchant customers. The arrangement should therefore incorporate appropriate AML controls tailored to these risks, including continuous monitoring of the vendor's compliance posture and transaction activities facilitated through the API delivery channel, to mitigate potential vulnerabilities related to money laundering or terrorist financing exploitation.", "riskCategoryId": "22222222-2222-2222-2222-222222222224"}	\N	2026-09-28 08:01:23.926326+00
1ef07d6d-0bcb-4701-b959-29bc5482e230	\N	9534f3f0-685a-4450-bfc0-983f2d16f7d9	NarrativeSection	fe5cfe98-0efc-4524-a1db-1aabb69d89b4	AiDrafted	\N	system/AI	{"id": "fe5cfe98-0efc-4524-a1db-1aabb69d89b4", "status": "AiDrafted", "updated_at": "2026-09-28T08:01:14.669485+00:00", "assessment_id": "9534f3f0-685a-4450-bfc0-983f2d16f7d9", "narrative_text": "The proposed business change involves onboarding a Malta-based vendor, QA corrected value, as a card settlement processor with access to cardholder Personally Identifiable Information (PII) and settlement files. This vendor will process transactions primarily for retail cardholders and Money Services Business (MSB) merchants. The delivery channel for the vendor's services will be via an API, which constitutes a non-face-to-face interaction channel. \\n\\nAccording to the FFIEC BSA/AML Manual section on Risks Associated with Money Laundering and Terrorist Financing: Customers, certain products and services, such as those involving electronic funds transfers and limited face-to-face contact, are inherently vulnerable to money laundering risks. The non-face-to-face nature of the API delivery channel aligns with this identified risk due to limited direct customer interaction. The involvement of cardholder PII further elevates the risk profile given the sensitivity of the data accessed by the vendor. \\n\\nIt is therefore critical that the bank has identified, measured, and mitigated the risks posed by onboarding this vendor, especially concerning the protection of PII and the oversight of transaction processing for retail cardholders and MSB merchants through electronic means. Ensuring robust controls and ongoing monitoring consistent with the bank's risk management framework will be essential to address the inherent vulnerabilities highlighted in the supervisory guidance.", "risk_category_id": "22222222-2222-2222-2222-222222222222", "updated_by_user_id": null, "unsupported_claim_flags": []}	{"text": "The onboarding of the Malta-based vendor, QA, introduces heightened Financial Crimes Risk due to the vendor's access to cardholder Personally Identifiable Information (PII) and settlement files. According to the FFIEC BSA/AML Manual, products and services involving rapid movement of funds or limited face-to-face contact present inherent vulnerabilities to money laundering and terrorist financing risks. This vendor operates through an API delivery channel, which is non-face-to-face, further emphasizing the risk profile as detailed in the policy excerpt on Products and Services (Risks Associated with Money Laundering and Terrorist Financing). The affected customer base includes retail cardholders and Money Services Business (MSB) merchants, both groups subject to potential exploitation if controls are insufficient. Given the vendor’s Malta jurisdiction, these factors require thorough risk identification, measurement, and mitigation prior to the vendor’s engagement to align with supervisory expectations.", "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	\N	2026-09-28 08:01:30.191563+00
7a100d0d-5ed9-4889-b3ee-9dc73ab69b55	\N	9534f3f0-685a-4450-bfc0-983f2d16f7d9	NarrativeSection	fe5cfe98-0efc-4524-a1db-1aabb69d89b4	AnalystEdited	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "fe5cfe98-0efc-4524-a1db-1aabb69d89b4", "status": "AiDrafted", "updated_at": "2026-09-28T08:01:30.191563+00:00", "assessment_id": "9534f3f0-685a-4450-bfc0-983f2d16f7d9", "narrative_text": "The onboarding of the Malta-based vendor, QA, introduces heightened Financial Crimes Risk due to the vendor's access to cardholder Personally Identifiable Information (PII) and settlement files. According to the FFIEC BSA/AML Manual, products and services involving rapid movement of funds or limited face-to-face contact present inherent vulnerabilities to money laundering and terrorist financing risks. This vendor operates through an API delivery channel, which is non-face-to-face, further emphasizing the risk profile as detailed in the policy excerpt on Products and Services (Risks Associated with Money Laundering and Terrorist Financing). The affected customer base includes retail cardholders and Money Services Business (MSB) merchants, both groups subject to potential exploitation if controls are insufficient. Given the vendor’s Malta jurisdiction, these factors require thorough risk identification, measurement, and mitigation prior to the vendor’s engagement to align with supervisory expectations.", "risk_category_id": "22222222-2222-2222-2222-222222222222", "updated_by_user_id": null, "unsupported_claim_flags": []}	{"text": "QA analyst narrative: vendor in Malta processes cardholder PII via API; enhanced due diligence and contractual audit rights required.", "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	Tightened wording and added EDD requirement	2026-09-28 08:01:32.251464+00
daa0377c-fde2-4dc5-a5be-db8338f061fa	\N	9534f3f0-685a-4450-bfc0-983f2d16f7d9	NarrativeSection	0338c9b2-a2a5-4004-a183-f3d02286bb56	AnalystReviewed	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"status": "AnalystReviewed", "riskCategoryId": "22222222-2222-2222-2222-222222222223"}	\N	2026-09-28 08:01:32.557284+00
24f83c74-b1ae-440b-bb3c-1fc775d53b94	\N	9534f3f0-685a-4450-bfc0-983f2d16f7d9	NarrativeSection	59d6e75a-6bb2-4339-b408-3c2ab91119cf	AnalystReviewed	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"status": "AnalystReviewed", "riskCategoryId": "22222222-2222-2222-2222-222222222224"}	\N	2026-09-28 08:01:32.846283+00
05713175-20c3-4b03-bfed-6676d577e63c	\N	9534f3f0-685a-4450-bfc0-983f2d16f7d9	RiskScore	084b8a1f-26d9-4a7a-a0f8-f8b0dd964f87	Calculated	\N	system/AI	\N	{"inherent": 4, "residual": 3.3200, "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	\N	2026-09-28 08:01:33.976207+00
3da39de7-e64b-46b7-8795-bc8452df9fc0	\N	9534f3f0-685a-4450-bfc0-983f2d16f7d9	RiskScore	f3d226e4-791f-4c55-8789-11757b9595c7	Calculated	\N	system/AI	\N	{"inherent": 1, "residual": 0.150, "riskCategoryId": "22222222-2222-2222-2222-222222222223"}	\N	2026-09-28 08:01:34.315434+00
cfd6232b-aaa2-459b-a7b5-4425aece48b8	\N	9534f3f0-685a-4450-bfc0-983f2d16f7d9	RiskScore	4f316764-37c7-448c-975c-b4868a164853	Calculated	\N	system/AI	\N	{"inherent": 3, "residual": 2.5750, "riskCategoryId": "22222222-2222-2222-2222-222222222224"}	\N	2026-09-28 08:01:34.672233+00
597f2949-c6bf-4aef-82b3-b4e9d5b5e1f7	a6bbfac6-7b11-45b5-8c48-74c1efc1a343	\N	Attachment	be3ee544-3fa1-453d-8c8f-e4b1b9e49f2c	Uploaded	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"version": 1, "fileName": "control-matrix.xlsx"}	\N	2026-09-28 08:04:43.766197+00
91c95443-804c-4b8e-a08a-144da610d554	\N	fe6f95b7-3a35-4799-9eb2-e3239a6a3674	PolicyReliance	6cd74099-ccbc-4699-aefd-f45423aaf769	Decided	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"decision": "ReliedUpon", "policyChunkId": "e7a09ebd-9c1f-4779-8499-fa131c4a77c4"}	\N	2026-09-28 08:05:41.654158+00
33ef2f46-ef06-49c8-9bdf-4ae34c642d96	\N	9534f3f0-685a-4450-bfc0-983f2d16f7d9	NarrativeSection	fe5cfe98-0efc-4524-a1db-1aabb69d89b4	AnalystEdited	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "fe5cfe98-0efc-4524-a1db-1aabb69d89b4", "status": "AnalystEdited", "updated_at": "2026-09-28T08:01:32.251464+00:00", "assessment_id": "9534f3f0-685a-4450-bfc0-983f2d16f7d9", "narrative_text": "QA analyst narrative: vendor in Malta processes cardholder PII via API; enhanced due diligence and contractual audit rights required.", "risk_category_id": "22222222-2222-2222-2222-222222222222", "updated_by_user_id": "4fa322d3-2245-44ef-b664-1a804442db23", "unsupported_claim_flags": []}	{"text": "post-finalize tamper", "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	QA lock test	2026-09-28 08:01:50.20594+00
2fe77854-1d6e-4d5e-a979-0d3b76950811	\N	9534f3f0-685a-4450-bfc0-983f2d16f7d9	RiskScore	084b8a1f-26d9-4a7a-a0f8-f8b0dd964f87	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "084b8a1f-26d9-4a7a-a0f8-f8b0dd964f87", "scored_by": "System", "created_at": "2026-09-28T08:01:33.976207+00:00", "is_override": true, "assessment_id": "9534f3f0-685a-4450-bfc0-983f2d16f7d9", "inherent_rating": 4.00, "override_reason": "Vendor has had two prior regulatory findings", "residual_rating": 2.50, "risk_category_id": "22222222-2222-2222-2222-222222222222", "created_by_user_id": null, "control_ids_credited": [], "control_effectiveness": 0.800, "mitigation_factor_applied": 0.850}	{"residual": 0.5, "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	QA lock test	2026-09-28 08:01:50.484804+00
946cba54-2673-46b6-8dbc-9c1f6c7f58e7	\N	9534f3f0-685a-4450-bfc0-983f2d16f7d9	CategoryMapping	b0a2383d-86c3-42e5-bdc6-dca43318c191	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"isActive": true, "riskCategoryId": "22222222-2222-2222-2222-222222222221"}	QA lock test	2026-09-28 08:01:50.767304+00
af2172de-dbdc-437a-987a-3049b52992ea	540ffca2-0e67-4ed9-9e72-39e1aa12152d	90b8631a-dba0-43a1-b722-92176fd4bd13	CommitteeVote	9ff4a58e-7d55-40ce-b4e3-1e4ed7b6f9e9	Voted	083ecfe5-aa01-4703-9168-762f0065078f	human	\N	{"vote": "ApproveWithConditions", "rationale": null, "conditionsText": ""}	\N	2026-09-28 08:01:53.200029+00
8f63db86-cc19-4ad6-b255-9b29283c807e	540ffca2-0e67-4ed9-9e72-39e1aa12152d	90b8631a-dba0-43a1-b722-92176fd4bd13	CommitteeVote	9ff4a58e-7d55-40ce-b4e3-1e4ed7b6f9e9	Voted	083ecfe5-aa01-4703-9168-762f0065078f	human	\N	{"vote": "Defer", "rationale": "   ", "conditionsText": null}	\N	2026-09-28 08:01:54.010869+00
69e600da-18fc-47cd-88a6-e9334662204e	540ffca2-0e67-4ed9-9e72-39e1aa12152d	90b8631a-dba0-43a1-b722-92176fd4bd13	CommitteeVote	2e63d1f6-39ae-4720-9e7a-4fc3e9f64d5e	Voted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"vote": "Approve", "rationale": null, "conditionsText": null}	\N	2026-09-28 08:01:54.808251+00
e1b69c6d-3f60-4d26-b16f-3e7eae499c1b	540ffca2-0e67-4ed9-9e72-39e1aa12152d	90b8631a-dba0-43a1-b722-92176fd4bd13	CommitteeDecision	a384e789-cf84-43da-9aaf-fde6164f0b3a	Decisioned	\N	system/AI	\N	{"resolution": "Deferred", "conditionsText": null}	\N	2026-09-28 08:01:54.955342+00
ecfdc7bc-b4e0-4e73-8765-5c08de50b81b	2afd7b9b-a899-466e-82e2-e58da781599a	\N	ChangeRequest	2afd7b9b-a899-466e-82e2-e58da781599a	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609280759] API probe - re-vote", "status": "Submitted", "changeType": "Feature"}	\N	2026-09-28 08:01:58.467666+00
a5eb0f5c-6fb4-4679-b06b-77f6f3d18f87	2afd7b9b-a899-466e-82e2-e58da781599a	c00848c0-50fa-4a02-bcf8-e7967c9a92c9	Assessment	c00848c0-50fa-4a02-bcf8-e7967c9a92c9	Finalized	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"finalizedBy": "4fa322d3-2245-44ef-b664-1a804442db23"}	\N	2026-09-28 08:01:59.186728+00
f384313f-006d-4468-b8b2-7d435f462024	2afd7b9b-a899-466e-82e2-e58da781599a	c00848c0-50fa-4a02-bcf8-e7967c9a92c9	ChangeRequest	2afd7b9b-a899-466e-82e2-e58da781599a	Routed	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"status": "PendingCommittee"}	\N	2026-09-28 08:01:59.485028+00
a4ab6c2e-31fb-44df-a465-74cefd3a0893	2afd7b9b-a899-466e-82e2-e58da781599a	c00848c0-50fa-4a02-bcf8-e7967c9a92c9	CommitteeVote	e05c4d38-31a7-4bb9-ac92-fc91a25c1904	Voted	083ecfe5-aa01-4703-9168-762f0065078f	human	\N	{"vote": "Approve", "rationale": null, "conditionsText": null}	\N	2026-09-28 08:01:59.860064+00
515f3d60-2b2b-4ad2-aea8-22c32914f9a4	2afd7b9b-a899-466e-82e2-e58da781599a	c00848c0-50fa-4a02-bcf8-e7967c9a92c9	CommitteeVote	e05c4d38-31a7-4bb9-ac92-fc91a25c1904	Voted	083ecfe5-aa01-4703-9168-762f0065078f	human	\N	{"vote": "Reject", "rationale": "changed my mind", "conditionsText": null}	\N	2026-09-28 08:02:00.338606+00
1cef20bc-c1fb-422d-89d4-f22c4c9fe802	617f16d3-e50b-487c-a31d-cedbbc7b572a	9534f3f0-685a-4450-bfc0-983f2d16f7d9	CommitteeVote	52692955-461b-4e60-824c-70d09a9b9db7	Voted	083ecfe5-aa01-4703-9168-762f0065078f	human	\N	{"vote": "ApproveWithConditions", "rationale": null, "conditionsText": "Annual on-site audit of the vendor; PII encrypted at rest"}	\N	2026-09-28 08:02:04.057771+00
6743bc8a-232a-4413-876c-e2f25591cb09	617f16d3-e50b-487c-a31d-cedbbc7b572a	9534f3f0-685a-4450-bfc0-983f2d16f7d9	CommitteeVote	3a727d50-e5b6-49b6-af29-00c92226ea6e	Voted	fa142c1c-58cc-4666-b135-7768a2ab33f0	human	\N	{"vote": "Approve", "rationale": null, "conditionsText": null}	\N	2026-09-28 08:02:04.514087+00
9e0f4fff-1f8e-41e3-aa4c-6c60ccc704a1	617f16d3-e50b-487c-a31d-cedbbc7b572a	9534f3f0-685a-4450-bfc0-983f2d16f7d9	CommitteeDecision	39adaf62-f4e8-4489-b9c6-342b0d1a70ec	Decisioned	\N	system/AI	\N	{"resolution": "ApprovedWithConditions", "conditionsText": "Jordan Blake: Annual on-site audit of the vendor; PII encrypted at rest"}	\N	2026-09-28 08:02:04.661138+00
6d050b46-73a0-41b6-ba49-89a370952ac0	617f16d3-e50b-487c-a31d-cedbbc7b572a	\N	MockSystemsFeedback	617f16d3-e50b-487c-a31d-cedbbc7b572a	Pushed	\N	system	\N	{"goLive": true, "resolution": "ApprovedWithConditions", "ratingSummary": "Approved with conditions: Jordan Blake: Annual on-site audit of the vendor; PII encrypted at rest"}	\N	2026-09-28 08:02:04.853344+00
b087ae94-6498-4a10-a82a-b3bfc755ccf4	a3e3e745-edef-45d1-a62f-c20dbb048de0	\N	ChangeRequest	a3e3e745-edef-45d1-a62f-c20dbb048de0	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609280759] API probe - config versioning", "status": "Submitted", "changeType": "CustomerSegment"}	\N	2026-09-28 08:02:14.349673+00
6d8e2168-b12e-40a4-ae0c-93f63f7f8b66	\N	\N	ScoringConfig	8e746b29-2cb4-4d95-b1df-652b1e30ed44	ConfigChanged	374a3158-6dfa-41f2-9a4d-3d1091dffacf	human	\N	{"riskCategoryId": "22222222-2222-2222-2222-222222222222", "maxMitigationFactor": 0.8}	QA: in-flight isolation test (restored immediately)	2026-09-28 08:02:14.977569+00
2e8de9a4-2635-4d8a-95a6-cf625e432801	\N	fef65e9f-675f-4a97-bed4-ab32decd986a	RiskScore	b9112532-ef77-485f-a8bc-aa20b58970f4	Calculated	\N	system/AI	\N	{"inherent": 3, "residual": 2.200, "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	\N	2026-09-28 08:02:15.295051+00
c5e656b0-f408-476d-b36a-393a497e8df1	\N	\N	ScoringConfig	1830ad2f-5abd-463a-a291-7d9e399632f6	ConfigChanged	374a3158-6dfa-41f2-9a4d-3d1091dffacf	human	\N	{"riskCategoryId": "22222222-2222-2222-2222-222222222222", "maxMitigationFactor": 0.85}	QA: restore baseline after TC-API-102	2026-09-28 08:02:15.645747+00
eca52f82-46b3-4deb-89fe-4a9efa003200	\N	\N	WorkflowRule	742e09d9-5a4e-434d-ac19-004b675bc2bd	ConfigChanged	374a3158-6dfa-41f2-9a4d-3d1091dffacf	human	\N	{"ruleKey": "CommitteeQuorum", "ruleValue": {"quorum": 2}}	QA: re-save unchanged value	2026-09-28 08:02:19.022231+00
181de6cb-3b41-4f40-aba3-a1b404be3030	e7983599-9aee-492c-8444-8764ae4892d9	\N	ChangeRequest	e7983599-9aee-492c-8444-8764ae4892d9	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609280759] API probe - actor spoofing", "status": "Submitted", "changeType": "Process"}	\N	2026-09-28 08:02:27.812065+00
a1f9474f-af01-47e9-8e43-e42e67192ff8	e7983599-9aee-492c-8444-8764ae4892d9	8a3f06ba-72ed-4b2c-bb1c-b6c92f890f3f	Assessment	8a3f06ba-72ed-4b2c-bb1c-b6c92f890f3f	Finalized	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"finalizedBy": "a6a709a7-65e7-4a90-9b58-cbbaec1d651a"}	\N	2026-09-28 08:02:28.502291+00
b234faaf-8e80-49b3-9980-a29db12ad5a5	\N	\N	ScoringConfig	4ecf4722-7cc2-4d06-91e9-7bca8133a76e	ConfigChanged	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"riskCategoryId": "22222222-2222-2222-2222-222222222222", "maxMitigationFactor": 0.85}	QA: RBAC probe - value unchanged	2026-09-28 08:02:28.788005+00
56b7003f-7e74-43dd-bca8-48f77195e0f8	663e4342-4b4a-43ef-b6c2-a088ef3ce1cc	\N	ChangeRequest	663e4342-4b4a-43ef-b6c2-a088ef3ce1cc	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609280759] long AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", "status": "Submitted", "changeType": "Feature"}	\N	2026-09-28 08:02:44.593376+00
04f7b07c-db28-4d51-92ea-321c3f714494	a6bbfac6-7b11-45b5-8c48-74c1efc1a343	\N	ChangeRequest	a6bbfac6-7b11-45b5-8c48-74c1efc1a343	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609280759] UI lifecycle - onboard Malta settlement vendor", "status": "Submitted", "changeType": "Vendor"}	\N	2026-09-28 08:04:26.91279+00
e6459ef7-9376-4b4a-a426-4933799645c6	a6bbfac6-7b11-45b5-8c48-74c1efc1a343	\N	ExternalSnapshot	a6bbfac6-7b11-45b5-8c48-74c1efc1a343	Ingested	\N	system	\N	{"hasVendor": true, "hasProduct": false, "hasCustomer": false}	\N	2026-09-28 08:04:26.992822+00
27b54973-4e5f-4393-8b57-dd1c98860641	a6bbfac6-7b11-45b5-8c48-74c1efc1a343	\N	Attachment	f81b2017-2a58-4223-9909-bcf0f23738ba	Uploaded	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"version": 1, "fileName": "vendor-due-diligence.pdf"}	\N	2026-09-28 08:04:33.182421+00
9da6262c-53fe-443d-91aa-1eb345fef564	a6bbfac6-7b11-45b5-8c48-74c1efc1a343	\N	Attachment	5e353e31-d23f-4f9b-aa73-6e14170baa87	Uploaded	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"version": 1, "fileName": "product-spec.docx"}	\N	2026-09-28 08:04:38.404736+00
9af2ec60-1331-450e-92af-01e3edc12495	\N	fe6f95b7-3a35-4799-9eb2-e3239a6a3674	PolicyReliance	be4c6fdb-4452-4ef0-b93b-8f9d8aac2fe8	Decided	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"decision": "ReliedUpon", "policyChunkId": "539e307e-5d18-454b-a33c-fbcf3ff8c407"}	\N	2026-09-28 08:05:43.166572+00
c6d81eb8-8d6d-4c25-bd2e-4b3bbdadda72	a6bbfac6-7b11-45b5-8c48-74c1efc1a343	\N	ExtractedField	c6640e81-9700-45a5-b538-fdf7511ed13a	AiExtracted	\N	system/AI	\N	{"value": null, "fieldKey": "vendor_name", "confidence": 0, "needsReview": true}	\N	2026-09-28 08:06:00.140989+00
949a97d4-12fa-4ca6-8bce-7ebd6d9a6a75	\N	fe6f95b7-3a35-4799-9eb2-e3239a6a3674	NarrativeSection	20191a3c-5862-48eb-af12-ced7e96486cb	AnalystEdited	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "20191a3c-5862-48eb-af12-ced7e96486cb", "status": "AiDrafted", "updated_at": "2026-09-28T08:06:28.501187+00:00", "assessment_id": "fe6f95b7-3a35-4799-9eb2-e3239a6a3674", "narrative_text": "The proposed business change involves onboarding QuickPay Processing Ltd, based in Malta, as a card settlement processor that will receive cardholder Personally Identifiable Information (PII) and settlement files via an API. This introduces considerations under the Customers & Entities risk category as outlined in the FFIEC BSA/AML Manual concerning money laundering and terrorist financing risks associated with customers. According to the cited policy section, certain categories of customers and entities are recognized to present elevated money laundering risks, including those with complex profiles such as non-resident aliens or entities operating in higher-risk sectors. A key element of mitigating these risks involves applying a risk-based customer due diligence program tailored to the customer’s inherent risk, including scaling the level of scrutiny accordingly. Given that QuickPay Processing Ltd is a vendor residing in Malta, a jurisdiction that could pose varying levels of risk, due diligence should confirm whether the entity or its underlying customer base falls into elevated risk categories requiring enhanced scrutiny. However, no specific facts were provided regarding QuickPay Processing Ltd’s risk profile or its categorization under the elevated risk groups highlighted in the policy, thus limiting a full risk assessment. Consequently, adherence to the risk-based due diligence approach per the referenced policy is essential to ensure the vendor relationship does not inadvertently expose the bank to money laundering or terrorist financing risks associated with customer profiles referenced in the cited section.", "risk_category_id": "22222222-2222-2222-2222-222222222222", "updated_by_user_id": null, "unsupported_claim_flags": ["QuickPay Processing Ltd operates in a higher-risk sector", "QuickPay Processing Ltd is a non-resident alien entity", "Enhanced due diligence has been performed on QuickPay Processing Ltd"]}	{"text": "QA analyst narrative: onboarding a Malta-domiciled settlement processor with API access to cardholder PII. EDD and annual audit rights required.", "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	Added EDD requirement and tightened wording (QA)	2026-09-28 08:06:52.983354+00
baa3779e-6e53-4275-884d-af446e9f181a	a6bbfac6-7b11-45b5-8c48-74c1efc1a343	fe6f95b7-3a35-4799-9eb2-e3239a6a3674	Assessment	fe6f95b7-3a35-4799-9eb2-e3239a6a3674	Finalized	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"finalizedBy": "4fa322d3-2245-44ef-b664-1a804442db23"}	\N	2026-09-28 08:07:26.002355+00
b8d19f32-c7ed-400f-9a08-afdc22174f82	\N	fe6f95b7-3a35-4799-9eb2-e3239a6a3674	PolicyReliance	44bcc9d2-5546-4be4-aee0-1c726f94b5d3	Decided	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"decision": "ReliedUpon", "policyChunkId": "79e625c1-e99c-43d0-9c93-4f2ee8b6f914"}	\N	2026-09-28 08:05:44.337023+00
52a5bc91-ac54-4455-a0a8-69f71dc92951	\N	fe6f95b7-3a35-4799-9eb2-e3239a6a3674	NarrativeSection	20191a3c-5862-48eb-af12-ced7e96486cb	AiDrafted	\N	system/AI	\N	{"text": "The proposed business change involves onboarding QuickPay Processing Ltd, based in Malta, as a card settlement processor that will receive cardholder Personally Identifiable Information (PII) and settlement files via an API. This introduces considerations under the Customers & Entities risk category as outlined in the FFIEC BSA/AML Manual concerning money laundering and terrorist financing risks associated with customers. According to the cited policy section, certain categories of customers and entities are recognized to present elevated money laundering risks, including those with complex profiles such as non-resident aliens or entities operating in higher-risk sectors. A key element of mitigating these risks involves applying a risk-based customer due diligence program tailored to the customer’s inherent risk, including scaling the level of scrutiny accordingly. Given that QuickPay Processing Ltd is a vendor residing in Malta, a jurisdiction that could pose varying levels of risk, due diligence should confirm whether the entity or its underlying customer base falls into elevated risk categories requiring enhanced scrutiny. However, no specific facts were provided regarding QuickPay Processing Ltd’s risk profile or its categorization under the elevated risk groups highlighted in the policy, thus limiting a full risk assessment. Consequently, adherence to the risk-based due diligence approach per the referenced policy is essential to ensure the vendor relationship does not inadvertently expose the bank to money laundering or terrorist financing risks associated with customer profiles referenced in the cited section.", "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	\N	2026-09-28 08:06:28.501187+00
846c2060-cc4e-496c-bd9e-64907c673599	\N	fe6f95b7-3a35-4799-9eb2-e3239a6a3674	NarrativeSection	6549925c-e621-4abb-b0bc-6b8b004c68e8	AiDrafted	\N	system/AI	\N	{"text": "The proposed onboarding of QuickPay Processing Ltd, a Malta-based vendor, as the card settlement processor involves the transmission of cardholder personally identifiable information (PII) and settlement files via an API. This change directly implicates the Delivery Channels risk category as outlined in the FFIEC BSA/AML Manual, specifically regarding risks associated with money laundering and terrorist financing through delivery channels. The policy underscores that non-face-to-face transaction channels and reliance on third-party agents can diminish a bank's direct ability to verify customer identity and intent, thereby increasing inherent risk (Risks Associated with Money Laundering and Terrorist Financing - Delivery Channels).\\n\\nGiven that QuickPay Processing Ltd will be integrated as a third-party service provider handling sensitive customer information remotely, the associated operational model aligns with the policy’s focus on increased risk resulting from third-party reliance. Therefore, this vendor onboarding must be carefully risk-assessed in accordance with the policy to ensure that appropriate controls are implemented to mitigate the potential reduction in direct identity verification capabilities and to manage the elevated exposure to financial crime threats through this delivery channel.", "riskCategoryId": "22222222-2222-2222-2222-222222222224"}	\N	2026-09-28 08:06:33.804772+00
d5e09dec-fde9-4cbd-a021-57d6d00fa8cd	\N	fe6f95b7-3a35-4799-9eb2-e3239a6a3674	NarrativeSection	2f34680d-b8de-4e93-a4fa-581cee259c5d	AiDrafted	\N	system/AI	\N	{"text": "The proposed business change involves onboarding QuickPay Processing Ltd, a vendor based in Malta, as a card settlement processor. This vendor will handle cardholder personally identifiable information (PII) and settlement files transmitted via an API. Given that Malta is the geographic location where the vendor operates, geographic risk factors must be considered in accordance with the FFIEC BSA/AML Manual guidance on Risks Associated with Money Laundering and Terrorist Financing. Specifically, risk assessment should consider whether Malta is identified by the Financial Action Task Force (FATF) as having strategic AML/CFT deficiencies, whether it is subject to any Office of Foreign Assets Control (OFAC) sanctions programs, or if it is designated as a domestic High Intensity Financial Crime Area (HIFCA) relevant to the bank's operations.\\n\\nAs there are no extracted facts indicating that Malta currently holds any such high-risk designations or sanctions, the baseline geographic risk associated with this vendor onboarding appears standard. Nonetheless, consistent with policy, the bank should apply additional scrutiny to products, customers, and transactions linked to Malta to mitigate potential exposure to geographic-based money laundering or terrorist financing risks, ensuring ongoing monitoring and compliance with all applicable regulatory expectations [Risks Associated with Money Laundering and Terrorist Financing - Geographic Locations].", "riskCategoryId": "22222222-2222-2222-2222-222222222223"}	\N	2026-09-28 08:06:38.854888+00
02b7211f-ab70-4e1a-918a-8bf95e41c471	\N	fe6f95b7-3a35-4799-9eb2-e3239a6a3674	NarrativeSection	6549925c-e621-4abb-b0bc-6b8b004c68e8	AnalystReviewed	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"status": "AnalystReviewed", "riskCategoryId": "22222222-2222-2222-2222-222222222224"}	\N	2026-09-28 08:06:53.972435+00
b757e506-320a-4bfe-8a6f-cb357e7e8f6d	\N	fe6f95b7-3a35-4799-9eb2-e3239a6a3674	NarrativeSection	2f34680d-b8de-4e93-a4fa-581cee259c5d	AnalystReviewed	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"status": "AnalystReviewed", "riskCategoryId": "22222222-2222-2222-2222-222222222223"}	\N	2026-09-28 08:06:54.452973+00
814e982a-da23-4bce-9e33-58bf9eb80552	\N	fe6f95b7-3a35-4799-9eb2-e3239a6a3674	RiskScore	ab482d8a-12cb-4dfb-985d-0ab80248da75	Calculated	\N	system/AI	\N	{"inherent": 5, "residual": 4.150, "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	\N	2026-09-28 08:07:00.896623+00
2be844f4-455f-4579-b211-c88c7c81756d	\N	fe6f95b7-3a35-4799-9eb2-e3239a6a3674	RiskScore	cb339489-16bb-4e49-a0a2-14f8267f6537	Calculated	\N	system/AI	\N	{"inherent": 3, "residual": 2.5750, "riskCategoryId": "22222222-2222-2222-2222-222222222224"}	\N	2026-09-28 08:07:02.002292+00
552aef33-4d48-4666-8f73-d6f1777b2f5e	\N	fe6f95b7-3a35-4799-9eb2-e3239a6a3674	RiskScore	94cb527c-9be1-4297-b724-5d014f6a5632	Calculated	\N	system/AI	\N	{"inherent": 3, "residual": 2.5750, "riskCategoryId": "22222222-2222-2222-2222-222222222223"}	\N	2026-09-28 08:07:03.114893+00
e603bf79-f088-4f6e-a4e7-eb3ec2008f8c	\N	fe6f95b7-3a35-4799-9eb2-e3239a6a3674	RiskScore	ab482d8a-12cb-4dfb-985d-0ab80248da75	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "ab482d8a-12cb-4dfb-985d-0ab80248da75", "scored_by": "System", "created_at": "2026-09-28T08:07:00.896623+00:00", "is_override": false, "assessment_id": "fe6f95b7-3a35-4799-9eb2-e3239a6a3674", "inherent_rating": 5.00, "override_reason": null, "residual_rating": 4.15, "risk_category_id": "22222222-2222-2222-2222-222222222222", "created_by_user_id": null, "control_ids_credited": [], "control_effectiveness": 1.000, "mitigation_factor_applied": 0.850}	{"residual": 2.5, "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	Vendor had prior regulatory findings (QA)	2026-09-28 08:07:19.442648+00
eb3b485a-f6fe-45a1-83f2-30e274d3a5c0	a6bbfac6-7b11-45b5-8c48-74c1efc1a343	fe6f95b7-3a35-4799-9eb2-e3239a6a3674	ChangeRequest	a6bbfac6-7b11-45b5-8c48-74c1efc1a343	Routed	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"status": "PendingCommittee"}	\N	2026-09-28 08:07:26.873717+00
d98ccd5f-d63e-4938-8ca1-d0a0d39de28f	a6bbfac6-7b11-45b5-8c48-74c1efc1a343	fe6f95b7-3a35-4799-9eb2-e3239a6a3674	CommitteeVote	a977d8b1-462b-4304-b533-b031697ebe7c	Voted	083ecfe5-aa01-4703-9168-762f0065078f	human	\N	{"vote": "ApproveWithConditions", "rationale": null, "conditionsText": "Annual on-site audit of the vendor; cardholder PII encrypted at rest (QA)"}	\N	2026-09-28 08:08:03.996253+00
a58d7d9a-2253-436d-81a9-4126485519d9	a6bbfac6-7b11-45b5-8c48-74c1efc1a343	fe6f95b7-3a35-4799-9eb2-e3239a6a3674	CommitteeVote	460e2d3d-9500-498b-929a-bdfad398726e	Voted	fa142c1c-58cc-4666-b135-7768a2ab33f0	human	\N	{"vote": "Approve", "rationale": null, "conditionsText": null}	\N	2026-09-28 08:08:09.643373+00
363124c2-0b24-48af-aa28-6b33eafe9aea	a6bbfac6-7b11-45b5-8c48-74c1efc1a343	fe6f95b7-3a35-4799-9eb2-e3239a6a3674	CommitteeDecision	8bf3d37a-e50b-41f6-bbc2-c90046403831	Decisioned	\N	system/AI	\N	{"resolution": "ApprovedWithConditions", "conditionsText": "Jordan Blake: Annual on-site audit of the vendor; cardholder PII encrypted at rest (QA)"}	\N	2026-09-28 08:08:09.781125+00
798e6892-ff93-4d47-ad18-8777aefdacff	\N	\N	WorkflowRule	29b2108d-a40d-4ae3-a13d-105fe74b458d	ConfigChanged	374a3158-6dfa-41f2-9a4d-3d1091dffacf	human	\N	{"ruleKey": "CommitteeQuorum", "ruleValue": {"quorum": 2}}	QA: re-save unchanged quorum	2026-09-28 08:08:30.425024+00
f29f973d-ef82-4e95-9a7e-140967d13619	b3976f2e-4b74-4091-9aea-66af92b07bc5	\N	ChangeRequest	b3976f2e-4b74-4091-9aea-66af92b07bc5	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609280759] <img src=x onerror=\\"window.__xss=1\\"><script>window.__xss=2</script>", "status": "Submitted", "changeType": "Feature"}	\N	2026-09-28 08:08:38.758915+00
3ea0ac44-df3d-478f-96f1-bdd5362b4da0	a6bbfac6-7b11-45b5-8c48-74c1efc1a343	\N	MockSystemsFeedback	a6bbfac6-7b11-45b5-8c48-74c1efc1a343	Pushed	\N	system	\N	{"goLive": true, "resolution": "ApprovedWithConditions", "ratingSummary": "Approved with conditions: Jordan Blake: Annual on-site audit of the vendor; cardholder PII encrypted at rest (QA)"}	\N	2026-09-28 08:08:10.282871+00
780b3e27-8ef2-48f3-a9b6-13782c5b0f0a	\N	\N	ScoringConfig	6a62e7ad-be7f-4246-9f2f-7611b24fd97a	ConfigChanged	374a3158-6dfa-41f2-9a4d-3d1091dffacf	human	\N	{"riskCategoryId": "22222222-2222-2222-2222-222222222222", "maxMitigationFactor": 0.85}	QA: re-save unchanged baseline	2026-09-28 08:08:36.76768+00
6be6ff90-b1e6-4ace-a2fa-ee3c3f757467	455cb36d-c05b-46f3-bba4-2769c127a7d3	\N	ChangeRequest	455cb36d-c05b-46f3-bba4-2769c127a7d3	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "test", "status": "Submitted", "changeType": "Feature"}	\N	2026-09-28 08:26:01.922924+00
71f2fbd1-5767-48b1-b35b-5b027cf4d02d	455cb36d-c05b-46f3-bba4-2769c127a7d3	\N	ExternalSnapshot	455cb36d-c05b-46f3-bba4-2769c127a7d3	Ingested	\N	system	\N	{"hasVendor": false, "hasProduct": true, "hasCustomer": false}	\N	2026-09-28 08:26:02.007712+00
f4416041-aa32-42d6-89b3-c7e5cca4419f	455cb36d-c05b-46f3-bba4-2769c127a7d3	3e2b8e40-cfa0-46c2-b6d2-48ae9e85c649	Assessment	3e2b8e40-cfa0-46c2-b6d2-48ae9e85c649	Finalized	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"finalizedBy": "4fa322d3-2245-44ef-b664-1a804442db23"}	\N	2026-09-28 08:32:05.578264+00
f1dc5868-bc79-46a2-af5e-a23cdcc7863e	455cb36d-c05b-46f3-bba4-2769c127a7d3	3e2b8e40-cfa0-46c2-b6d2-48ae9e85c649	ChangeRequest	455cb36d-c05b-46f3-bba4-2769c127a7d3	Routed	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"status": "PendingCommittee"}	\N	2026-09-28 08:34:16.236599+00
9ec806b8-866e-4422-9b27-f712331029c3	7a379245-0ee3-414a-884d-de47fc4ae358	\N	ChangeRequest	7a379245-0ee3-414a-884d-de47fc4ae358	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-E2E 202609280838] Onboard QuickPay Processing Ltd (Malta) as the card settlement processor for the consumer debit and prepaid card programmes, including cardholder PII and daily settlement file exchange over API", "status": "Submitted", "changeType": "Vendor"}	\N	2026-09-28 08:39:13.123812+00
a48c17cc-803a-423b-8390-95908bfa5dce	7a379245-0ee3-414a-884d-de47fc4ae358	\N	ExternalSnapshot	7a379245-0ee3-414a-884d-de47fc4ae358	Ingested	\N	system	\N	{"hasVendor": true, "hasProduct": false, "hasCustomer": false}	\N	2026-09-28 08:39:13.20456+00
c5b19a8b-89df-4d6b-85dd-aa1127c4f085	7a379245-0ee3-414a-884d-de47fc4ae358	eb5c9dbb-e31b-4d8b-8820-d13aa90fabc1	Assessment	eb5c9dbb-e31b-4d8b-8820-d13aa90fabc1	Finalized	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"finalizedBy": "4fa322d3-2245-44ef-b664-1a804442db23"}	\N	2026-09-28 08:39:17.89468+00
f69dab29-1e56-49ff-9f68-b4f8190d2ed4	7a379245-0ee3-414a-884d-de47fc4ae358	eb5c9dbb-e31b-4d8b-8820-d13aa90fabc1	ChangeRequest	7a379245-0ee3-414a-884d-de47fc4ae358	Routed	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"status": "PendingCommittee"}	\N	2026-09-28 08:39:18.900804+00
cbf392f1-f23f-40fc-b170-83956aa5ef11	\N	1887751d-52fb-4229-b25e-a1a2204df89c	PolicyReliance	d7b23eae-4c0a-4c3d-96ad-4dfa62d59b83	Decided	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"decision": "ReliedUpon", "policyChunkId": "3f171e93-f2ca-40a4-af6a-18ede9021c9b"}	\N	2026-09-29 08:14:22.854733+00
6468bb92-efcd-410e-b13c-bc286fa4561d	\N	1887751d-52fb-4229-b25e-a1a2204df89c	PolicyReliance	f6337036-f3dc-42ff-a906-caa2ee9746b6	Decided	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"decision": "ReliedUpon", "policyChunkId": "3f171e93-f2ca-40a4-af6a-18ede9021c9b"}	\N	2026-09-29 08:14:23.364598+00
49375307-0b2e-4899-b5ae-0bd736e8de6b	\N	1887751d-52fb-4229-b25e-a1a2204df89c	PolicyReliance	05f8335b-d14c-44f3-abba-b68fca752941	Decided	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"decision": "NotRelevant", "policyChunkId": "3f171e93-f2ca-40a4-af6a-18ede9021c9b"}	\N	2026-09-29 08:14:23.849836+00
0878b779-9caf-4564-8c2e-7b5555067aeb	\N	1887751d-52fb-4229-b25e-a1a2204df89c	PolicyReliance	05f8335b-d14c-44f3-abba-b68fca752941	Decided	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"decision": "ReliedUpon", "policyChunkId": "3f171e93-f2ca-40a4-af6a-18ede9021c9b"}	\N	2026-09-29 08:14:24.304595+00
baabe364-1dc8-4ff7-bd06-65fd8fc22abd	\N	b2a913c6-c962-4dfd-9961-810e58affc32	CategoryMapping	3ca5da75-f679-4b1e-ade9-c535cf98336b	AiProposed	\N	system/AI	\N	{"citation": "FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Products and Services", "riskCategoryId": "22222222-2222-2222-2222-222222222221"}	\N	2026-09-29 10:07:45.86419+00
3afabab4-4e14-424a-89c2-eef7a85ca683	\N	b2a913c6-c962-4dfd-9961-810e58affc32	NarrativeSection	c8f7f7b8-f3fe-4f01-ab5e-2267260930a4	AiDrafted	\N	system/AI	\N	{"text": "The proposed product change, titled 'e2e shared test B,' is categorized under Products & Services risk as outlined in the FFIEC BSA/AML Manual section on Risks Associated with Money Laundering and Terrorist Financing: Products and Services. Although the change is labeled as a test with minimal descriptive detail, careful consideration of the risk category is warranted given the potential for new or modified products and services to introduce vulnerabilities to money laundering and terrorist financing risks. The absence of detailed facts or substantive policy excerpts beyond the general citation limits the ability to provide a thorough risk assessment at this time. Close alignment with the FFIEC guidance will be necessary to ensure that any product features do not inadvertently permit misuse or exploitation by illicit actors.", "riskCategoryId": "22222222-2222-2222-2222-222222222221"}	\N	2026-09-29 10:08:31.309683+00
5fa154bd-3ef0-43f3-8087-fc6db8933e8c	823b48e6-5235-4fdf-9aa9-17ceb9417cd5	\N	ChangeRequest	823b48e6-5235-4fdf-9aa9-17ceb9417cd5	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "Deployed AI verify", "status": "Submitted", "changeType": "Product"}	\N	2026-09-29 11:04:30.15356+00
8357cba9-21cc-4cab-9225-21c8aff13002	7a379245-0ee3-414a-884d-de47fc4ae358	eb5c9dbb-e31b-4d8b-8820-d13aa90fabc1	CommitteeVote	73d482ab-ef38-415f-bc9e-72967153175c	Voted	083ecfe5-aa01-4703-9168-762f0065078f	human	\N	{"vote": "Approve", "rationale": null, "conditionsText": null}	\N	2026-09-29 17:43:17.68689+00
1a35518a-9ce5-487d-82fc-52907b06cdde	7a379245-0ee3-414a-884d-de47fc4ae358	eb5c9dbb-e31b-4d8b-8820-d13aa90fabc1	CommitteeVote	d7c27797-bfdf-4d0c-a92c-c35fffdebe7c	Voted	fa142c1c-58cc-4666-b135-7768a2ab33f0	human	\N	{"vote": "Approve", "rationale": null, "conditionsText": null}	\N	2026-09-29 17:43:44.545607+00
c71fc811-77f9-401a-b5a4-ea3f64283b1e	7a379245-0ee3-414a-884d-de47fc4ae358	eb5c9dbb-e31b-4d8b-8820-d13aa90fabc1	CommitteeDecision	7eae9615-971e-40ee-9113-1e2c03d3fb6d	Decisioned	\N	system/AI	\N	{"resolution": "Approved", "conditionsText": null}	\N	2026-09-29 17:43:44.698289+00
fbaafd79-0a45-4b7c-b248-b30e60d91111	7a379245-0ee3-414a-884d-de47fc4ae358	\N	MockSystemsFeedback	7a379245-0ee3-414a-884d-de47fc4ae358	Pushed	\N	system	\N	{"goLive": true, "resolution": "Approved", "ratingSummary": "Low - approved without conditions"}	\N	2026-09-29 17:43:45.222421+00
18a62d78-eae0-44bd-9857-27bbd493ee6d	\N	3a72b012-35ca-4baf-be5d-4dafcf02cd11	CategoryMapping	8f53b248-81f2-4509-bc1f-753b4a2ddbae	AiProposed	\N	system/AI	\N	{"citation": "FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Products and Services", "riskCategoryId": "22222222-2222-2222-2222-222222222221"}	\N	2026-09-30 10:40:45.405304+00
dceb3178-db29-4abb-a66b-aab8287c6fc2	7a6b4b58-4a23-4844-8c3b-fd20377a720f	\N	ChangeRequest	7a6b4b58-4a23-4844-8c3b-fd20377a720f	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "New Product by Suleman", "status": "Submitted", "changeType": "Product"}	\N	2026-09-30 11:03:38.559476+00
c4cabe7e-272b-421f-a85d-6f426bfa6eed	7a6b4b58-4a23-4844-8c3b-fd20377a720f	\N	ExternalSnapshot	7a6b4b58-4a23-4844-8c3b-fd20377a720f	Ingested	\N	system	\N	{"hasVendor": false, "hasProduct": true, "hasCustomer": false}	\N	2026-09-30 11:03:39.630385+00
ff1a0b6b-a676-4cb4-9a1b-453326cb706b	846abe95-3e9a-438f-9b30-0c7097371a27	\N	ChangeRequest	846abe95-3e9a-438f-9b30-0c7097371a27	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "Launch Prepaid Settlement Card", "status": "Submitted", "changeType": "Product"}	\N	2026-09-30 11:15:53.3788+00
e08a3264-fad1-4016-9f59-09d39afa9361	846abe95-3e9a-438f-9b30-0c7097371a27	\N	ExternalSnapshot	846abe95-3e9a-438f-9b30-0c7097371a27	Ingested	\N	system	\N	{"hasVendor": false, "hasProduct": true, "hasCustomer": false}	\N	2026-09-30 11:15:56.789006+00
fbf56e4d-af05-4eb7-b85b-e06bec9e9934	7a6b4b58-4a23-4844-8c3b-fd20377a720f	\N	Attachment	1fa4e0f7-3a28-443a-9401-ccb24a01184d	Uploaded	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"version": 1, "fileName": "product-launch-brief.pdf"}	\N	2026-09-30 11:21:39.670473+00
bbe30ff3-0642-4532-b516-a9ca966feb6d	846abe95-3e9a-438f-9b30-0c7097371a27	\N	Attachment	17b2efa1-50d9-47e5-80af-b905522d548a	Uploaded	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"version": 1, "fileName": "product-launch-brief-Prepaid-Settlement-Card.pdf"}	\N	2026-09-30 11:23:10.755828+00
acc2cdf0-19b2-445c-8765-1f9b3896a3b7	\N	6e3cb87c-89cf-41ae-9629-15e5ae88b2ca	CategoryMapping	a18d102f-5680-4590-ac0c-8caf602fbf62	AiProposed	\N	system/AI	\N	{"citation": "FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Products and Services", "riskCategoryId": "22222222-2222-2222-2222-222222222221"}	\N	2026-09-30 11:37:35.869386+00
89b703d1-5a7e-4e90-b540-77a7d3a58345	\N	6e3cb87c-89cf-41ae-9629-15e5ae88b2ca	CategoryMapping	a18d102f-5680-4590-ac0c-8caf602fbf62	AiProposed	\N	system/AI	\N	{"citation": "FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Products and Services", "riskCategoryId": "22222222-2222-2222-2222-222222222221"}	\N	2026-09-30 11:38:53.533125+00
8618be80-6aa7-41ee-9364-67f49f740e7a	\N	6e3cb87c-89cf-41ae-9629-15e5ae88b2ca	CategoryMapping	5ea176d9-b9d2-4975-a663-adf059d1a74a	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"isActive": true, "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	Product targets cash-intensive small businesses (retail shops, restaurants) alongside retail consumers — cash-intensive business types are a named Customer & Entity risk factor in the FFIEC framework.	2026-09-30 11:39:19.23359+00
51a150bf-4027-47b5-88b3-7a2c01f23789	\N	6e3cb87c-89cf-41ae-9629-15e5ae88b2ca	CategoryMapping	fdd2eeb8-a780-449d-b674-2c678a93af0a	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"isActive": true, "riskCategoryId": "22222222-2222-2222-2222-222222222223"}	Cross-border transactions supported in 12 countries, including two FATF-monitored jurisdictions — this brings Geographic Locations into scope per FFIEC.	2026-09-30 11:39:49.804002+00
10371b4d-37b2-4c36-b718-4f4eff2cf41f	\N	6e3cb87c-89cf-41ae-9629-15e5ae88b2ca	CategoryMapping	32393fb5-efef-42eb-9704-3c9c345dfec6	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"isActive": true, "riskCategoryId": "22222222-2222-2222-2222-222222222224"}	online	2026-09-30 11:42:01.378758+00
5180a5d9-0f6a-46d7-a6d5-540662790b46	\N	6e3cb87c-89cf-41ae-9629-15e5ae88b2ca	CategoryMapping	5ea176d9-b9d2-4975-a663-adf059d1a74a	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "5ea176d9-b9d2-4975-a663-adf059d1a74a", "source": "AnalystAdded", "is_active": true, "created_at": "2026-09-30T11:39:19.23359+00:00", "ai_citation": null, "assessment_id": "6e3cb87c-89cf-41ae-9629-15e5ae88b2ca", "risk_category_id": "22222222-2222-2222-2222-222222222222", "created_by_user_id": "4fa322d3-2245-44ef-b664-1a804442db23"}	{"isActive": false, "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	Test remove reason	2026-09-30 11:48:41.557759+00
8567eaff-b4ec-4960-94c4-0432101dbffd	\N	6e3cb87c-89cf-41ae-9629-15e5ae88b2ca	CategoryMapping	5ea176d9-b9d2-4975-a663-adf059d1a74a	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "5ea176d9-b9d2-4975-a663-adf059d1a74a", "source": "AnalystAdded", "is_active": false, "created_at": "2026-09-30T11:39:19.23359+00:00", "ai_citation": null, "assessment_id": "6e3cb87c-89cf-41ae-9629-15e5ae88b2ca", "risk_category_id": "22222222-2222-2222-2222-222222222222", "created_by_user_id": "4fa322d3-2245-44ef-b664-1a804442db23"}	{"isActive": true, "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	Product targets cash-intensive small businesses alongside retail consumers - a named Customer and Entity risk factor in FFIEC.	2026-09-30 11:49:35.302592+00
ad9fed0c-23bc-49ea-a6f3-52a581482148	\N	6e3cb87c-89cf-41ae-9629-15e5ae88b2ca	CategoryMapping	32393fb5-efef-42eb-9704-3c9c345dfec6	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "32393fb5-efef-42eb-9704-3c9c345dfec6", "source": "AnalystAdded", "is_active": true, "created_at": "2026-09-30T11:42:01.378758+00:00", "ai_citation": null, "assessment_id": "6e3cb87c-89cf-41ae-9629-15e5ae88b2ca", "risk_category_id": "22222222-2222-2222-2222-222222222224", "created_by_user_id": "4fa322d3-2245-44ef-b664-1a804442db23"}	{"isActive": false, "riskCategoryId": "22222222-2222-2222-2222-222222222224"}	not aplicable	2026-09-30 11:50:55.552468+00
78bbf495-0e46-4ce4-af2d-4ce039467519	\N	6e3cb87c-89cf-41ae-9629-15e5ae88b2ca	PolicyReliance	bf9bb4a1-58d0-4feb-aba4-76650c050dea	Decided	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"decision": "ReliedUpon", "policyChunkId": "3f171e93-f2ca-40a4-af6a-18ede9021c9b"}	\N	2026-09-30 12:12:09.504099+00
f521c9b7-e86c-4ff1-b3c3-5f2f13a1d5ad	\N	6e3cb87c-89cf-41ae-9629-15e5ae88b2ca	PolicyReliance	f8851649-f53e-42d1-8a5e-5f505485f755	Decided	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"decision": "ReliedUpon", "policyChunkId": "4a27362f-c3e9-48a6-8e7d-538ca56e56a3"}	\N	2026-09-30 12:15:52.469383+00
a6502488-8f27-4b88-9c6b-93ccaae14791	846abe95-3e9a-438f-9b30-0c7097371a27	\N	ExtractedField	cbe140ca-c6dc-4bfc-9c59-a71957b45263	AiExtracted	\N	system/AI	\N	{"value": "Prepaid Settlement Card", "fieldKey": "product_name", "confidence": 1, "needsReview": false}	\N	2026-09-30 12:22:22.804245+00
cf555d68-32c5-4db2-b2af-a62ec21f88bf	846abe95-3e9a-438f-9b30-0c7097371a27	\N	ExtractedField	5a1fbad3-bea1-44ea-b955-0f974638ae37	AiExtracted	\N	system/AI	\N	{"value": "A reloadable prepaid debit card issued to retail and small-business customers, enabling domestic and cross-border point-of-sale and ATM transactions.", "fieldKey": "product_description", "confidence": 1, "needsReview": false}	\N	2026-09-30 12:22:23.24706+00
54dfaa32-80da-4a6d-978a-e02b7685baf9	846abe95-3e9a-438f-9b30-0c7097371a27	\N	ExtractedField	9d9b81fd-a7a8-45fb-be85-165abf747a7d	AiExtracted	\N	system/AI	\N	{"value": "Retail consumers and cash-intensive small businesses (e.g. retail shops, restaurants)", "fieldKey": "target_customers", "confidence": 1, "needsReview": false}	\N	2026-09-30 12:22:23.57541+00
c1c91cac-a81e-4b9c-92ae-ae1ad0f13182	846abe95-3e9a-438f-9b30-0c7097371a27	\N	ExtractedField	1c0eec56-bbb9-462b-b56c-22e35eebef1f	AiExtracted	\N	system/AI	\N	{"value": "No PEP or NRA customers targeted at launch", "fieldKey": "excluded_customer_types", "confidence": 1, "needsReview": false}	\N	2026-09-30 12:22:23.904359+00
b56c5343-3bff-4637-934a-46b27f66d467	846abe95-3e9a-438f-9b30-0c7097371a27	\N	ExtractedField	fc3e7458-dda1-426d-bcc5-ac421e57eb0c	AiExtracted	\N	system/AI	\N	{"value": "Card-present point-of-sale, ATM withdrawal, and card-not-present online transactions", "fieldKey": "transaction_types", "confidence": 1, "needsReview": false}	\N	2026-09-30 12:22:24.32362+00
24c7a3d2-9cf6-4ea4-8875-a35c3a7e103b	846abe95-3e9a-438f-9b30-0c7097371a27	\N	ExtractedField	c0928ba1-143f-47df-b681-5dc42349ee68	AiExtracted	\N	system/AI	\N	{"value": "Cross-border transactions supported in 12 countries including two FATF-monitored jurisdictions", "fieldKey": "cross_border_transaction_coverage", "confidence": 1, "needsReview": false}	\N	2026-09-30 12:22:24.743151+00
373fbeba-4b59-47c9-9a06-17da5a1cdc4c	846abe95-3e9a-438f-9b30-0c7097371a27	\N	ExtractedField	d60945d4-65cb-4c76-a886-4250224e7ba7	AiExtracted	\N	system/AI	\N	{"value": "Fully online (non-face-to-face) enrollment via mobile app; no branch visit required", "fieldKey": "onboarding_channel", "confidence": 1, "needsReview": false}	\N	2026-09-30 12:22:25.063849+00
49b3964a-da7b-4dad-80db-a823cd067a96	846abe95-3e9a-438f-9b30-0c7097371a27	\N	ExtractedField	f42ef83b-8108-47a6-b87c-d00f146dbad7	AiExtracted	\N	system/AI	\N	{"value": "QuickPay Processing Ltd", "fieldKey": "third_party_processors", "confidence": 1, "needsReview": false}	\N	2026-09-30 12:22:25.379271+00
3ed7bc53-101e-4133-ac22-46e415c06eb9	846abe95-3e9a-438f-9b30-0c7097371a27	\N	ExtractedField	4765ead5-6ed3-4825-ac65-4c0f4938e41c	AiExtracted	\N	system/AI	\N	{"value": "API-based daily settlement file exchange", "fieldKey": "third_party_data_exchange_method", "confidence": 1, "needsReview": false}	\N	2026-09-30 12:22:25.718134+00
8a181f51-1624-44bc-89fa-b041aa745393	846abe95-3e9a-438f-9b30-0c7097371a27	\N	ExtractedField	552c205c-267b-45ce-9386-00deabc8299e	AiExtracted	\N	system/AI	\N	{"value": "Cardholder PII (name, address, SSN last-4), transaction history, device fingerprint", "fieldKey": "data_handled", "confidence": 1, "needsReview": false}	\N	2026-09-30 12:22:26.038845+00
73085d13-ed19-47da-843d-ddb6f198e94c	846abe95-3e9a-438f-9b30-0c7097371a27	\N	ExtractedField	4765ead5-6ed3-4825-ac65-4c0f4938e41c	Corrected	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "4765ead5-6ed3-4825-ac65-4c0f4938e41c", "source": "AiExtracted", "field_key": "third_party_data_exchange_method", "confidence": 1.000, "updated_at": "2026-09-30T12:22:25.718134+00:00", "field_value": "API-based daily settlement file exchange", "needs_review": false, "attachment_id": "17b2efa1-50d9-47e5-80af-b905522d548a", "source_excerpt": "with API-based daily settlement file exchange.", "change_request_id": "846abe95-3e9a-438f-9b30-0c7097371a27", "updated_by_user_id": null}	{"value": "SFTP-based daily settlement file exchange (not real-time API)", "fieldKey": "third_party_data_exchange_method"}	Vendor kickoff call me confirm batch is SFTP , not real-time API	2026-09-30 12:29:14.792767+00
e508d719-eb53-4510-a6e3-f64eb7d27d79	\N	6e3cb87c-89cf-41ae-9629-15e5ae88b2ca	NarrativeSection	6222e9d0-a3fc-4b44-a2b6-cab617d1dd58	AiDrafted	\N	system/AI	\N	{"text": "The proposed launch of the Prepaid Settlement Card introduces a reloadable prepaid debit card product serving retail consumers and cash-intensive small businesses, facilitating both domestic and cross-border point-of-sale and ATM transactions. As noted in the FFIEC BSA/AML Manual section on Products and Services, prepaid access products possess inherent vulnerabilities to money laundering due to characteristics such as rapid fund movements and limited face-to-face interactions. The product's fully online onboarding process without branch visits accentuates these inherent risks, necessitating robust mitigation strategies and risk measurement prior to rollout.\\n\\nThe product supports cross-border transactions in 12 countries, including two jurisdictions monitored by FATF, which may elevate risks given the increased complexity and varying anti-money laundering frameworks internationally. The inclusion of card-not-present online transactions further accentuates the necessity for enhanced controls to detect and prevent illicit activity. Additionally, third-party processing arrangements with QuickPay Processing Ltd and the use of SFTP-based daily settlement file exchanges introduce considerations related to data security and transaction monitoring within third-party ecosystems.\\n\\nGiven these factors aligned with the cited FFIEC guidance, it is imperative that the bank has identified, measured, and established mitigation controls for the specific risks associated with this prepaid access product offering before launch, particularly addressing vulnerabilities arising from non-face-to-face enrollment and cross-border functionality (Risks Associated with Money Laundering and Terrorist Financing - Products and Services). The exclusion of PEP and non-resident alien customers at launch may reduce some risk layers but does not eliminate inherent risks tied to this product type and delivery channel.", "riskCategoryId": "22222222-2222-2222-2222-222222222221"}	\N	2026-09-30 12:29:43.414643+00
65a6354c-c0ee-449a-a56b-091a0a396786	\N	6e3cb87c-89cf-41ae-9629-15e5ae88b2ca	NarrativeSection	008d25c0-d694-4597-bf82-ae18cc0f29c5	AiDrafted	\N	system/AI	\N	{"text": "The introduction of the Prepaid Settlement Card, a reloadable prepaid debit product targeted at retail consumers and cash-intensive small businesses, involves specific money laundering and terrorist financing risks inherent to prepaid access instruments. According to the FFIEC BSA/AML Manual, prepaid access products such as general-purpose reloadable cards are vulnerable due to their potential to facilitate structuring below reporting thresholds and movement of value with limited identity verification. Consequently, effective customer due diligence must align proportionally with the product's funding, reload, and redemption features (Prepaid Access Customers). The card enables multiple transaction types, including card-present point-of-sale, ATM withdrawals, and card-not-present online transactions, across domestic and cross-border environments. Cross-border capabilities include 12 countries, with two FATF-monitored jurisdictions, further increasing the need for tailored AML controls (Products and Services). \\n\\nThe onboarding process is fully digital and non-face-to-face, conducted via a mobile app without branch visits, which elevates risks related to identity verification and customer authentication. The bank’s exclusion of politically exposed persons (PEPs) and non-resident aliens (NRAs) as initial customers partially mitigates heightened risk exposure at launch. Data collected during onboarding includes sensitive personally identifiable information (PII) such as name, address, and partial Social Security number, alongside transaction history and device fingerprinting to enhance risk profiling. The use of a third-party processor, QuickPay Processing Ltd, and reliance on daily settlement data exchange via SFTP rather than real-time APIs, underscores the importance of ongoing monitoring and timely information sharing to detect suspicious activity. \\n\\nIn summary, the Prepaid Settlement Card’s inherent vulnerabilities from rapid fund movement and limited face-to-face interaction require the bank to implement robust customer due diligence and transaction monitoring controls proportionate to the product’s features and risks, consistent with supervisory guidance in the FFIEC BSA/AML Manual sections on Products and Services and Prepaid Access Customers.", "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	\N	2026-09-30 12:30:02.150932+00
61bdbfa4-21f2-4bda-bfda-4120647041a7	\N	6e3cb87c-89cf-41ae-9629-15e5ae88b2ca	NarrativeSection	5f7f6f13-3b22-44db-b4f5-43178e599f4d	AiDrafted	\N	system/AI	\N	{"text": "The proposed Prepaid Settlement Card is a reloadable prepaid debit card offered to retail and small-business customers, facilitating domestic and cross-border point-of-sale and ATM transactions. Given the nature of prepaid access products, which are highlighted in the FFIEC BSA/AML Manual as inherently vulnerable to money laundering due to rapid fund movement and limited face-to-face contact, this product introduces geographic risks that require careful assessment and mitigation (Risks Associated with Money Laundering and Terrorist Financing - Products and Services). The card supports cross-border transactions in 12 countries, including two jurisdictions monitored by FATF, which amplifies geographic risk exposure and necessitates heightened due diligence controls to address potential financial crime threats associated with these locations.", "riskCategoryId": "22222222-2222-2222-2222-222222222223"}	\N	2026-09-30 12:30:18.644168+00
077f7b69-5dab-4a0c-af70-d6f35ca56522	\N	6e3cb87c-89cf-41ae-9629-15e5ae88b2ca	NarrativeSection	5f7f6f13-3b22-44db-b4f5-43178e599f4d	AiDrafted	\N	system/AI	{"id": "5f7f6f13-3b22-44db-b4f5-43178e599f4d", "status": "AiDrafted", "updated_at": "2026-09-30T12:30:18.644168+00:00", "assessment_id": "6e3cb87c-89cf-41ae-9629-15e5ae88b2ca", "narrative_text": "The proposed Prepaid Settlement Card is a reloadable prepaid debit card offered to retail and small-business customers, facilitating domestic and cross-border point-of-sale and ATM transactions. Given the nature of prepaid access products, which are highlighted in the FFIEC BSA/AML Manual as inherently vulnerable to money laundering due to rapid fund movement and limited face-to-face contact, this product introduces geographic risks that require careful assessment and mitigation (Risks Associated with Money Laundering and Terrorist Financing - Products and Services). The card supports cross-border transactions in 12 countries, including two jurisdictions monitored by FATF, which amplifies geographic risk exposure and necessitates heightened due diligence controls to address potential financial crime threats associated with these locations.", "risk_category_id": "22222222-2222-2222-2222-222222222223", "updated_by_user_id": null, "unsupported_claim_flags": ["The level of risk posed by the two FATF-monitored jurisdictions compared to other countries is significant."]}	{"text": "The proposed launch of the Prepaid Settlement Card introduces a reloadable prepaid debit product tailored for retail and small-business customers, including those engaged in cash-intensive activities, with functionalities enabling both domestic and cross-border point-of-sale and ATM transactions. Given the inherent vulnerabilities of prepaid access products to money laundering due to rapid fund movements and limited face-to-face contact, as noted in the supervisory guidance on geographic locations risk (Risks Associated with Money Laundering and Terrorist Financing - Products and Services), it is critical to assess the geographic risks tied to cross-border transactions. This product supports cross-border transactions in 12 countries, including two FATF-monitored jurisdictions, which elevates the importance of robust geographic risk management and ongoing monitoring for potential illicit activity stemming from higher-risk locations.\\n\\nThe onboarding process for the Prepaid Settlement Card is fully online without branch visits, which, combined with the product features, increases potential exposure to money laundering risks due to the non-face-to-face enrollment channel. However, the product does not target politically exposed persons (PEPs) or non-resident aliens (NRAs) at launch, narrowing certain customer risk dimensions. The involvement of the third-party processor QuickPay Processing Ltd and SFTP-based daily settlement file exchanges necessitates ensuring these partners have adequate controls to manage and monitor risks associated with geographic locations during transaction processing.\\n\\nOverall, the bank must ensure that its risk identification, measurement, and mitigation procedures fully incorporate the geographic risk considerations tied to cross-border prepaid card usage, particularly for the FATF-monitored jurisdictions covered. Appropriate transaction monitoring, customer due diligence, and oversight of third-party processing activities should be emphasized to address the geographic vulnerabilities associated with this prepaid access product as outlined in the FFIEC BSA/AML Manual risk framework.", "riskCategoryId": "22222222-2222-2222-2222-222222222223"}	\N	2026-09-30 12:30:45.269452+00
d953422d-89d8-4b93-a8ac-c79d9235d706	\N	6e3cb87c-89cf-41ae-9629-15e5ae88b2ca	NarrativeSection	5f7f6f13-3b22-44db-b4f5-43178e599f4d	AnalystEdited	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "5f7f6f13-3b22-44db-b4f5-43178e599f4d", "status": "AiDrafted", "updated_at": "2026-09-30T12:30:45.269452+00:00", "assessment_id": "6e3cb87c-89cf-41ae-9629-15e5ae88b2ca", "narrative_text": "The proposed launch of the Prepaid Settlement Card introduces a reloadable prepaid debit product tailored for retail and small-business customers, including those engaged in cash-intensive activities, with functionalities enabling both domestic and cross-border point-of-sale and ATM transactions. Given the inherent vulnerabilities of prepaid access products to money laundering due to rapid fund movements and limited face-to-face contact, as noted in the supervisory guidance on geographic locations risk (Risks Associated with Money Laundering and Terrorist Financing - Products and Services), it is critical to assess the geographic risks tied to cross-border transactions. This product supports cross-border transactions in 12 countries, including two FATF-monitored jurisdictions, which elevates the importance of robust geographic risk management and ongoing monitoring for potential illicit activity stemming from higher-risk locations.\\n\\nThe onboarding process for the Prepaid Settlement Card is fully online without branch visits, which, combined with the product features, increases potential exposure to money laundering risks due to the non-face-to-face enrollment channel. However, the product does not target politically exposed persons (PEPs) or non-resident aliens (NRAs) at launch, narrowing certain customer risk dimensions. The involvement of the third-party processor QuickPay Processing Ltd and SFTP-based daily settlement file exchanges necessitates ensuring these partners have adequate controls to manage and monitor risks associated with geographic locations during transaction processing.\\n\\nOverall, the bank must ensure that its risk identification, measurement, and mitigation procedures fully incorporate the geographic risk considerations tied to cross-border prepaid card usage, particularly for the FATF-monitored jurisdictions covered. Appropriate transaction monitoring, customer due diligence, and oversight of third-party processing activities should be emphasized to address the geographic vulnerabilities associated with this prepaid access product as outlined in the FFIEC BSA/AML Manual risk framework.", "risk_category_id": "22222222-2222-2222-2222-222222222223", "updated_by_user_id": null, "unsupported_claim_flags": ["The third-party processor QuickPay Processing Ltd has adequate controls to manage geographic location risks.", "Ongoing monitoring programs are sufficient to mitigate geographic risks related to the FATF-monitored jurisdictions."]}	{"text": "The proposed launch of the Prepaid Settlement Card introduces a reloadable prepaid debit product tailored for retail and small-business customers, including those engaged in cash-intensive activities, with functionalities enabling both domestic and cross-border point-of-sale and ATM transactions. Given the inherent vulnerabilities of prepaid access products to money laundering due to rapid fund movements and limited face-to-face contact, as noted in the supervisory guidance on geographic locations risk (Risks Associated with Money Laundering and Terrorist Financing - Products and Services), it is critical to assess the geographic risks tied to cross-border transactions. This product supports cross-border transactions in UAE countries, including two FATF-monitored jurisdictions, which elevates the importance of robust geographic risk management and ongoing monitoring for potential illicit activity stemming from higher-risk locations. The onboarding process for the Prepaid Settlement Card is fully online without branch visits, which, combined with the product features, increases potential exposure to money laundering risks due to the non-face-to-face enrollment channel. However, the product does not target politically exposed persons (PEPs) or non-resident aliens (NRAs) at launch, narrowing certain customer risk dimensions. The involvement of the third-party processor QuickPay Processing Ltd and SFTP-based daily settlement file exchanges necessitates ensuring these partners have adequate controls to manage and monitor risks associated with geographic locations during transaction processing. Overall, the bank must ensure that its risk identification, measurement, and mitigation procedures fully incorporate the geographic risk considerations tied to cross-border prepaid card usage, particularly for the FATF-monitored jurisdictions covered. Appropriate transaction monitoring, customer due diligence, and oversight of third-party processing activities should be emphasized to address the geographic vulnerabilities associated with this prepaid access product as outlined in the FFIEC BSA/AML Manual risk framework.\\n\\n", "riskCategoryId": "22222222-2222-2222-2222-222222222223"}	Added explicit mention of the two FATF-monitored jurisdictions per FCRM committee's request	2026-09-30 12:36:53.697345+00
4ea37666-3eb3-4cac-8a84-fbd1c39cc054	\N	6e3cb87c-89cf-41ae-9629-15e5ae88b2ca	NarrativeSection	008d25c0-d694-4597-bf82-ae18cc0f29c5	AnalystReviewed	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"status": "AnalystReviewed", "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	\N	2026-09-30 12:37:35.176081+00
78162f34-2707-4349-a7b3-0c4f181cda31	\N	6e3cb87c-89cf-41ae-9629-15e5ae88b2ca	NarrativeSection	6222e9d0-a3fc-4b44-a2b6-cab617d1dd58	AnalystReviewed	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"status": "AnalystReviewed", "riskCategoryId": "22222222-2222-2222-2222-222222222221"}	\N	2026-09-30 12:37:40.080982+00
28a353f5-3422-4bcf-b0f7-c45b60dbb4d7	\N	6e3cb87c-89cf-41ae-9629-15e5ae88b2ca	RiskScore	c2cb451b-6603-4562-9929-bba492469b1c	Calculated	\N	system/AI	\N	{"inherent": 4, "residual": 3.4900, "riskCategoryId": "22222222-2222-2222-2222-222222222221"}	\N	2026-09-30 12:45:44.753631+00
f2a94884-81d4-4b8a-820d-d0352f78cd40	\N	6e3cb87c-89cf-41ae-9629-15e5ae88b2ca	RiskScore	0de5b7f2-5e12-4a5e-9754-40d7cc58bc22	Calculated	\N	system/AI	\N	{"inherent": 3, "residual": 2.44750, "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	\N	2026-09-30 12:46:34.907676+00
6799c957-0e1e-4a7a-8f0e-59509f6982b2	\N	6e3cb87c-89cf-41ae-9629-15e5ae88b2ca	RiskScore	7c7bcae2-197d-48d3-96da-9a9673a4138a	Calculated	\N	system/AI	\N	{"inherent": 4, "residual": 3.4050, "riskCategoryId": "22222222-2222-2222-2222-222222222223"}	\N	2026-09-30 12:47:00.318032+00
bafe7728-8085-48c9-9a74-3445dd96748a	846abe95-3e9a-438f-9b30-0c7097371a27	6e3cb87c-89cf-41ae-9629-15e5ae88b2ca	Assessment	6e3cb87c-89cf-41ae-9629-15e5ae88b2ca	Finalized	1329f6a2-3450-438e-8a5f-b7b9ae219b67	human	\N	{"finalizedBy": "1329f6a2-3450-438e-8a5f-b7b9ae219b67"}	\N	2026-09-30 12:57:37.763475+00
791663ff-86f9-44d0-97e8-27bfbb80ebf3	846abe95-3e9a-438f-9b30-0c7097371a27	6e3cb87c-89cf-41ae-9629-15e5ae88b2ca	ChangeRequest	846abe95-3e9a-438f-9b30-0c7097371a27	Routed	1329f6a2-3450-438e-8a5f-b7b9ae219b67	human	\N	{"status": "PendingCommittee"}	\N	2026-09-30 12:58:02.239242+00
1001615a-0302-41c4-a533-1a4c9ac57629	846abe95-3e9a-438f-9b30-0c7097371a27	6e3cb87c-89cf-41ae-9629-15e5ae88b2ca	CommitteeVote	2ea2d8a2-0d00-4606-a69e-b07f641f9c74	Voted	083ecfe5-aa01-4703-9168-762f0065078f	human	\N	{"vote": "Approve", "rationale": null, "conditionsText": null}	\N	2026-09-30 13:04:53.589426+00
305da069-d673-4703-a881-6dd498a2a4e0	846abe95-3e9a-438f-9b30-0c7097371a27	6e3cb87c-89cf-41ae-9629-15e5ae88b2ca	ChangeRequest	846abe95-3e9a-438f-9b30-0c7097371a27	Routed	1329f6a2-3450-438e-8a5f-b7b9ae219b67	human	\N	{"status": "PendingCommittee"}	\N	2026-09-30 14:16:29.71782+00
f48b5fb1-a3cc-493e-b8ff-44313edb1ff0	\N	0db7ab6a-e107-4f80-93c6-05c73df4c70b	CategoryMapping	e9eb54ce-2095-4687-a137-80d84a600d3f	AiProposed	\N	system/AI	\N	{"citation": "FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Products and Services", "riskCategoryId": "22222222-2222-2222-2222-222222222221"}	\N	2026-09-30 14:32:49.729582+00
ec2f50bc-3511-439e-a8b7-e42f9a54c823	\N	b2a913c6-c962-4dfd-9961-810e58affc32	NarrativeSection	c8f7f7b8-f3fe-4f01-ab5e-2267260930a4	AiDrafted	\N	system/AI	{"id": "c8f7f7b8-f3fe-4f01-ab5e-2267260930a4", "status": "AiDrafted", "updated_at": "2026-09-29T10:08:31.309683+00:00", "assessment_id": "b2a913c6-c962-4dfd-9961-810e58affc32", "narrative_text": "The proposed product change, titled 'e2e shared test B,' is categorized under Products & Services risk as outlined in the FFIEC BSA/AML Manual section on Risks Associated with Money Laundering and Terrorist Financing: Products and Services. Although the change is labeled as a test with minimal descriptive detail, careful consideration of the risk category is warranted given the potential for new or modified products and services to introduce vulnerabilities to money laundering and terrorist financing risks. The absence of detailed facts or substantive policy excerpts beyond the general citation limits the ability to provide a thorough risk assessment at this time. Close alignment with the FFIEC guidance will be necessary to ensure that any product features do not inadvertently permit misuse or exploitation by illicit actors.", "risk_category_id": "22222222-2222-2222-2222-222222222221", "updated_by_user_id": null, "unsupported_claim_flags": ["The specific risks this product change might introduce are unclear due to lack of detailed information.", "The product's features will be evaluated for compliance with AML/CTF controls upon further documentation."]}	{"text": "This section is intended to assess the Products & Services risk category for the proposed change titled \\"e2e shared test B\\" under the FFIEC BSA/AML Manual's guidance on Risks Associated with Money Laundering and Terrorist Financing: Products and Services. However, no policy excerpts have been marked as relied-upon and no facts have been extracted from submitted documentation to support this assessment.\\n\\nAs a result, this narrative cannot substantively evaluate the money laundering or terrorist financing risk exposure introduced by the proposed change, characterize the nature of the product or service being modified, or reference specific control mechanisms, customer due diligence considerations, or monitoring enhancements that would typically inform a Products & Services risk determination.\\n\\nBefore this risk category assessment can be completed in accordance with the FFIEC BSA/AML Manual, additional documentation should be submitted and reviewed, including a detailed description of the product or service change, applicable policy or procedure excerpts governing the product type, and any supporting analysis addressing customer usage patterns, transaction typologies, or geographic risk factors associated with the change.", "riskCategoryId": "22222222-2222-2222-2222-222222222221"}	\N	2026-09-30 14:48:12.934927+00
21af5fd8-f822-4674-a92d-d2116d2a04f1	\N	0db7ab6a-e107-4f80-93c6-05c73df4c70b	NarrativeSection	4cb41c7b-857f-4603-9f73-cd5f4b5432ef	AiDrafted	\N	system/AI	\N	{"text": "This assessment addresses the proposed change titled \\"Deployed AI verify,\\" which involves testing an Anthropic workspace-scoped call within the bank's deployed development environment. The change has been categorized under the Products & Services risk category, consistent with the FFIEC BSA/AML Manual's guidance on money laundering and terrorist financing risks associated with new products and services, which requires that financial institutions evaluate the inherent risk profile of new or modified products, services, and delivery channels before and during their introduction.\\n\\nAt this time, no specific policy excerpts beyond the applicable FFIEC citation and no extracted document facts have been supplied to support a detailed, fact-based risk characterization of this change. Consequently, this narrative cannot substantiate the nature of the underlying product functionality, its customer-facing impact, transaction volumes, data flows, or any compensating controls that may apply, as none of this information was provided in the source materials made available for this review.\\n\\nGiven the absence of supporting documentation, the Products & Services risk category determination for this change should be treated as preliminary. Before this assessment can be finalized, additional documentation describing the functional scope of the Anthropic workspace-scoped call, its intended production use (if any), and any associated customer or transactional touchpoints should be obtained and evaluated against the FFIEC BSA/AML Manual's Products and Services risk factors.", "riskCategoryId": "22222222-2222-2222-2222-222222222221"}	\N	2026-09-30 17:27:06.52086+00
09047623-aec8-4685-b6aa-0ab311e6ee33	846abe95-3e9a-438f-9b30-0c7097371a27	\N	Attachment	dd75b413-3645-47b7-a441-2693ab1e4aa4	Uploaded	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"version": 1, "fileName": "Team Registration for Panel Review.xlsx"}	\N	2026-10-01 17:34:49.752133+00
6ab1a5e5-cf17-4398-be37-10cdeba090df	d92baa78-c3dc-4ea5-ac3f-89b79959397d	\N	ChangeRequest	d92baa78-c3dc-4ea5-ac3f-89b79959397d	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-FT 05Oct] Onboard QuickPay Processing as card settlement vendor", "status": "Submitted", "changeType": "Vendor"}	\N	2026-10-05 09:11:38.107328+00
8389a06d-fb26-436e-8695-11086f26409c	d92baa78-c3dc-4ea5-ac3f-89b79959397d	\N	ExternalSnapshot	d92baa78-c3dc-4ea5-ac3f-89b79959397d	Ingested	\N	system	\N	{"hasVendor": true, "hasProduct": false, "hasCustomer": false}	\N	2026-10-05 09:11:38.238757+00
9ae6be16-fe37-4a24-9eaf-1c5c46b5a527	1676366d-3ee4-4d55-993d-afcd3dc38b9a	\N	ChangeRequest	1676366d-3ee4-4d55-993d-afcd3dc38b9a	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-FT 05Oct] Move KYC refresh to online self-service", "status": "Submitted", "changeType": "Process"}	\N	2026-10-05 09:13:19.771242+00
1ea9c0d0-ca40-4cfa-8427-883cabc7a124	bf57f2fb-8d22-4567-a0d3-6eed60680461	\N	ChangeRequest	bf57f2fb-8d22-4567-a0d3-6eed60680461	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-FT 05Oct] Onboard new vendor Aurora Ledger Ltd (not in VMS)", "status": "Submitted", "changeType": "Vendor"}	\N	2026-10-05 09:13:31.147194+00
a77fb5f9-10f5-4c0e-96a6-07470174ace9	d92baa78-c3dc-4ea5-ac3f-89b79959397d	\N	Attachment	1a7cd49f-7d55-4106-94a9-d00af9130b4b	Uploaded	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"version": 1, "fileName": "vendor-due-diligence.pdf"}	\N	2026-10-05 09:13:58.979738+00
befb37f2-edfe-4a27-9ed6-2bae2e695167	d92baa78-c3dc-4ea5-ac3f-89b79959397d	\N	Attachment	6d166471-482b-4657-8640-bd29a57e4a43	Uploaded	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"version": 1, "fileName": "product-spec.docx"}	\N	2026-10-05 09:14:10.255263+00
41ff001b-ab8e-4588-a278-3a83cef878f0	d92baa78-c3dc-4ea5-ac3f-89b79959397d	\N	Attachment	618d9907-2cde-4efc-9731-27e2ada90ff4	Uploaded	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"version": 1, "fileName": "control-matrix.xlsx"}	\N	2026-10-05 09:14:21.258062+00
74482f88-5fa9-444d-9608-a699c12a30ba	\N	386b9113-a53e-4b90-a396-35e574b2bfa3	CategoryMapping	92b68792-1baa-4557-8baf-802a03fe8e51	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"isActive": true, "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	Vendor receives cardholder PII; customer-entity exposure	2026-10-05 09:16:25.868279+00
79504a06-a43a-46a0-971d-c17c45f10a73	\N	386b9113-a53e-4b90-a396-35e574b2bfa3	CategoryMapping	ecfe53b8-fb9d-4433-afbb-b134775afd63	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"isActive": true, "riskCategoryId": "22222222-2222-2222-2222-222222222224"}	Non-face-to-face API delivery via third-party processor	2026-10-05 09:17:39.703211+00
1840afd6-6c47-4b9a-9e16-1385356ae7e7	\N	386b9113-a53e-4b90-a396-35e574b2bfa3	CategoryMapping	d1b4fea3-f3b4-447e-9335-740a61e29112	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"isActive": true, "riskCategoryId": "22222222-2222-2222-2222-222222222223"}	Vendor jurisdiction Malta	2026-10-05 09:17:47.7952+00
dcaf5215-8ed2-4a87-b3cb-b994601255f1	\N	386b9113-a53e-4b90-a396-35e574b2bfa3	CategoryMapping	5c2a6d47-9b0a-402e-afe0-a9945b1f8620	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"isActive": true, "riskCategoryId": "22222222-2222-2222-2222-222222222221"}	Card settlement product exposure - removed later in test	2026-10-05 09:17:57.895533+00
a6c764ab-e9e1-4020-8362-68ad544cebb6	\N	386b9113-a53e-4b90-a396-35e574b2bfa3	CategoryMapping	5c2a6d47-9b0a-402e-afe0-a9945b1f8620	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "5c2a6d47-9b0a-402e-afe0-a9945b1f8620", "source": "AnalystAdded", "is_active": true, "created_at": "2026-10-05T09:17:57.895533+00:00", "ai_citation": null, "assessment_id": "386b9113-a53e-4b90-a396-35e574b2bfa3", "risk_category_id": "22222222-2222-2222-2222-222222222221", "created_by_user_id": "4fa322d3-2245-44ef-b664-1a804442db23"}	{"isActive": false, "riskCategoryId": "22222222-2222-2222-2222-222222222221"}	Not a product change - vendor onboarding only	2026-10-05 09:18:06.043337+00
ff8ec200-c6e6-4079-bfd4-395910624dd9	\N	386b9113-a53e-4b90-a396-35e574b2bfa3	PolicyReliance	909d3030-9b63-4f9a-ae7a-a4f40d366480	Decided	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"decision": "ReliedUpon", "policyChunkId": "e7a09ebd-9c1f-4779-8499-fa131c4a77c4"}	\N	2026-10-05 09:19:20.208628+00
b2be8613-7318-4c9f-8b55-865d1752a8ff	\N	386b9113-a53e-4b90-a396-35e574b2bfa3	PolicyReliance	333d04f7-1549-4ec1-9a40-db4253be21c9	Decided	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"decision": "NotRelevant", "policyChunkId": "4f51dd86-f2b8-41c7-88ad-2d44e8a295c2"}	\N	2026-10-05 09:19:23.244867+00
d4071b10-6d76-4de9-b417-3484630bab81	\N	b2a913c6-c962-4dfd-9961-810e58affc32	NarrativeSection	c8f7f7b8-f3fe-4f01-ab5e-2267260930a4	AnalystEdited	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "c8f7f7b8-f3fe-4f01-ab5e-2267260930a4", "status": "AiDrafted", "updated_at": "2026-09-30T14:48:12.934927+00:00", "assessment_id": "b2a913c6-c962-4dfd-9961-810e58affc32", "narrative_text": "This section is intended to assess the Products & Services risk category for the proposed change titled \\"e2e shared test B\\" under the FFIEC BSA/AML Manual's guidance on Risks Associated with Money Laundering and Terrorist Financing: Products and Services. However, no policy excerpts have been marked as relied-upon and no facts have been extracted from submitted documentation to support this assessment.\\n\\nAs a result, this narrative cannot substantively evaluate the money laundering or terrorist financing risk exposure introduced by the proposed change, characterize the nature of the product or service being modified, or reference specific control mechanisms, customer due diligence considerations, or monitoring enhancements that would typically inform a Products & Services risk determination.\\n\\nBefore this risk category assessment can be completed in accordance with the FFIEC BSA/AML Manual, additional documentation should be submitted and reviewed, including a detailed description of the product or service change, applicable policy or procedure excerpts governing the product type, and any supporting analysis addressing customer usage patterns, transaction typologies, or geographic risk factors associated with the change.", "risk_category_id": "22222222-2222-2222-2222-222222222221", "updated_by_user_id": null, "unsupported_claim_flags": ["The specific nature of the product or service change and its features", "Whether the change increases, decreases, or has no material effect on money laundering/terrorist financing risk", "Any existing controls, monitoring, or due diligence measures applicable to this product change", "Customer base or transaction volume characteristics associated with the change", "Geographic or channel risk factors relevant to the proposed change"]}	{"text": "QA-FT 05Oct analyst edit: The product change introduces prepaid-style settlement exposure. Customer due diligence and transaction monitoring must cover reload limits and cross-border usage, per the FFIEC Products and Services section.", "riskCategoryId": "22222222-2222-2222-2222-222222222221"}	QA-FT 05Oct long reason check (US-6.1 AC3 - reason must never be truncated). The AI draft states no facts were available, so the analyst replaces it with an assessment grounded on the product description and the FFIEC Products and Services guidance. END-OF-REASON-MARKER	2026-10-05 09:21:58.873896+00
4686783a-b071-4110-9d8f-3a8495659942	\N	b2a913c6-c962-4dfd-9961-810e58affc32	RiskScore	0469fc35-fb26-4a05-8385-d92cbedbf4a6	Calculated	\N	system/AI	\N	{"inherent": 3, "residual": 2.5750, "riskCategoryId": "22222222-2222-2222-2222-222222222221"}	\N	2026-10-05 09:23:44.2286+00
8e68873d-78f1-406a-b8b7-ac77261a2490	\N	b2a913c6-c962-4dfd-9961-810e58affc32	RiskScore	0469fc35-fb26-4a05-8385-d92cbedbf4a6	Calculated	\N	system/AI	\N	{"inherent": 4, "residual": 3.4900, "riskCategoryId": "22222222-2222-2222-2222-222222222221"}	\N	2026-10-05 09:24:11.516137+00
a9914973-b0c4-4dfe-a0a4-225e51058318	\N	b2a913c6-c962-4dfd-9961-810e58affc32	RiskScore	0469fc35-fb26-4a05-8385-d92cbedbf4a6	Calculated	\N	system/AI	\N	{"inherent": 1, "residual": 0.150, "riskCategoryId": "22222222-2222-2222-2222-222222222221"}	\N	2026-10-05 09:24:18.675111+00
f35b7f68-f350-4836-a71c-233680e65062	\N	b2a913c6-c962-4dfd-9961-810e58affc32	RiskScore	0469fc35-fb26-4a05-8385-d92cbedbf4a6	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "0469fc35-fb26-4a05-8385-d92cbedbf4a6", "scored_by": "System", "created_at": "2026-10-05T09:24:18.675111+00:00", "is_override": false, "assessment_id": "b2a913c6-c962-4dfd-9961-810e58affc32", "inherent_rating": 1.00, "override_reason": null, "residual_rating": 0.15, "risk_category_id": "22222222-2222-2222-2222-222222222221", "created_by_user_id": null, "control_ids_credited": ["76333a56-763e-4ea4-938c-a97d372a91de", "f2e10b03-e672-42da-9295-9093b5a6fd84", "c0e2f410-3642-469a-94d2-f9d8eac0b2b2", "7ee7aaa5-4b80-4304-a149-7aa95e7c57b6"], "control_effectiveness": 1.000, "mitigation_factor_applied": 0.850}	{"residual": 2.2, "riskCategoryId": "22222222-2222-2222-2222-222222222221"}	QA-FT 05Oct: prepaid limits verified in pilot; analyst judgement lowers residual	2026-10-05 09:26:12.253575+00
d5a0a7ce-5fa4-43bf-923a-d52ca3757fb4	\N	b2a913c6-c962-4dfd-9961-810e58affc32	PolicyReliance	8823ad55-aa8f-47f3-8d4c-8a7721601a16	Decided	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"decision": "ReliedUpon", "policyChunkId": "3f171e93-f2ca-40a4-af6a-18ede9021c9b"}	\N	2026-10-05 09:26:40.845797+00
ec49474c-9322-4396-9514-bef80dde44a4	ac11f587-ee4f-40e6-a72f-e7e8f6be308a	b2a913c6-c962-4dfd-9961-810e58affc32	Assessment	b2a913c6-c962-4dfd-9961-810e58affc32	Finalized	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"finalizedBy": "4fa322d3-2245-44ef-b664-1a804442db23"}	\N	2026-10-05 09:26:47.271953+00
0dfb8024-785a-46f1-bda2-7b44b215bb06	ac11f587-ee4f-40e6-a72f-e7e8f6be308a	b2a913c6-c962-4dfd-9961-810e58affc32	Assessment	b2a913c6-c962-4dfd-9961-810e58affc32	Finalized	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"finalizedBy": "4fa322d3-2245-44ef-b664-1a804442db23"}	\N	2026-10-05 09:27:25.125327+00
3b3ab3c4-0e43-48fe-a345-b03076ff6724	ac11f587-ee4f-40e6-a72f-e7e8f6be308a	b2a913c6-c962-4dfd-9961-810e58affc32	ChangeRequest	ac11f587-ee4f-40e6-a72f-e7e8f6be308a	Routed	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"status": "PendingCommittee"}	\N	2026-10-05 09:27:51.790776+00
57a89b1f-0033-426a-9857-87f96401c6e0	ac11f587-ee4f-40e6-a72f-e7e8f6be308a	b2a913c6-c962-4dfd-9961-810e58affc32	CommitteeVote	ce6878ba-bc6c-4b38-8e90-0ee7588c2552	Voted	083ecfe5-aa01-4703-9168-762f0065078f	human	\N	{"vote": "ApproveWithConditions", "rationale": null, "conditionsText": "QA-FT 05Oct conditions: quarterly review of prepaid reload limits; enhanced monitoring for cross-border loads"}	\N	2026-10-05 09:29:28.909751+00
f875695b-9694-4037-96ec-f1fa99263a69	ac11f587-ee4f-40e6-a72f-e7e8f6be308a	b2a913c6-c962-4dfd-9961-810e58affc32	CommitteeVote	6fc78b7e-bb68-46f6-aac9-1fff11930f2f	Voted	fa142c1c-58cc-4666-b135-7768a2ab33f0	human	\N	{"vote": "Approve", "rationale": null, "conditionsText": null}	\N	2026-10-05 09:30:52.73098+00
a77899fe-e2bf-4e16-9122-a104179c7dae	ac11f587-ee4f-40e6-a72f-e7e8f6be308a	b2a913c6-c962-4dfd-9961-810e58affc32	CommitteeDecision	8e4c5104-d0fa-49aa-9b6b-847896aa2335	Decisioned	\N	system/AI	\N	{"resolution": "ApprovedWithConditions", "conditionsText": "Jordan Blake: QA-FT 05Oct conditions: quarterly review of prepaid reload limits; enhanced monitoring for cross-border loads"}	\N	2026-10-05 09:30:52.886257+00
e8a912f8-e59c-47a4-87bf-e349c399d83c	1676366d-3ee4-4d55-993d-afcd3dc38b9a	\N	Clarification	fceaa5f1-5137-41f3-a947-015ab0677b33	Requested	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"question": "QA-FT 05Oct: Which customer segments are in scope for the online KYC refresh, and what identity verification method will be used?"}	\N	2026-10-05 09:31:42.445852+00
7142e3b6-2c2b-408b-bfa7-d6802b63cf0c	\N	\N	WorkflowRule	cf69adeb-1295-410f-b718-6f8df81c25ae	ConfigChanged	374a3158-6dfa-41f2-9a4d-3d1091dffacf	human	\N	{"ruleKey": "QA_FT_NoAuthProbe", "ruleValue": {"probe": true}}	QA-FT TC-ACL-01 unauthenticated write probe	2026-10-05 09:35:38.340803+00
835281b2-c564-4d96-ac13-490ade7ef123	a7ae047c-a52c-40dd-a9d6-7840e8e7a87a	\N	ChangeRequest	a7ae047c-a52c-40dd-a9d6-7840e8e7a87a	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-FT 05Oct] Stale vendor id (TC-MCK-02)", "status": "Submitted", "changeType": "Vendor"}	\N	2026-10-05 09:36:23.377083+00
332152e1-30d1-4cab-971a-08ef86986d20	\N	8d5b74bf-e52d-4e0d-8606-7e0cf1100d7c	CategoryMapping	e415d52c-2791-499f-b7fe-d52f9933fb8b	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"isActive": true, "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	QA-FT TC-REV-04 add	2026-10-05 09:37:26.387653+00
4827551a-fba3-4bdf-b342-2c71c8fcaefe	\N	8d5b74bf-e52d-4e0d-8606-7e0cf1100d7c	CategoryMapping	e415d52c-2791-499f-b7fe-d52f9933fb8b	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	{"id": "e415d52c-2791-499f-b7fe-d52f9933fb8b", "source": "AnalystAdded", "is_active": true, "created_at": "2026-10-05T09:37:26.387653+00:00", "ai_citation": null, "assessment_id": "8d5b74bf-e52d-4e0d-8606-7e0cf1100d7c", "risk_category_id": "22222222-2222-2222-2222-222222222222", "created_by_user_id": "4fa322d3-2245-44ef-b664-1a804442db23"}	{"isActive": false, "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	QA-FT TC-REV-04 deactivate all	2026-10-05 09:37:26.762964+00
cde57947-99e5-4082-b599-9d42d258a98a	\N	386b9113-a53e-4b90-a396-35e574b2bfa3	RiskScore	8b677411-ad1b-48fe-bccb-2b524cd36409	Calculated	\N	system/AI	\N	{"inherent": 3, "residual": 2.5750, "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	\N	2026-10-05 09:37:53.371267+00
5853204e-5e6c-4d6f-96ac-53d02c2d432f	\N	\N	ScoringConfig	7350651e-ef4f-4e18-9f91-ce93c127f47c	ConfigChanged	374a3158-6dfa-41f2-9a4d-3d1091dffacf	human	\N	{"riskCategoryId": "22222222-2222-2222-2222-222222222222", "maxMitigationFactor": 0.8}	QA-FT 05Oct TC-CFG-01: tighten Customers & Entities cap to 0.80 (restored after test)	2026-10-05 09:38:43.86919+00
27beef5d-b0b9-4e98-84ac-a22fa8714435	\N	386b9113-a53e-4b90-a396-35e574b2bfa3	RiskScore	8b677411-ad1b-48fe-bccb-2b524cd36409	Calculated	\N	system/AI	\N	{"inherent": 3, "residual": 2.5750, "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	\N	2026-10-05 09:39:03.041304+00
37d5e045-2319-4bd9-9935-e14808b63b9a	\N	e58102ff-6105-4be7-8f8a-befe3c0167ac	CategoryMapping	e9615daa-90fc-4bd6-bc32-830bda18af10	Overridden	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"isActive": true, "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	QA-FT TC-CFG-01 new assessment	2026-10-05 09:39:04.058453+00
deb900e2-697c-48f9-987c-730f9b622876	\N	e58102ff-6105-4be7-8f8a-befe3c0167ac	RiskScore	3979d7dd-8ddd-491a-a527-46bfe451cb99	Calculated	\N	system/AI	\N	{"inherent": 3, "residual": 2.6000, "riskCategoryId": "22222222-2222-2222-2222-222222222222"}	\N	2026-10-05 09:39:04.486728+00
227db7b3-1fbe-49fc-a676-c7d669233fbe	\N	\N	ScoringConfig	7697af84-945b-4d44-89a8-1a3c8dcb8b2e	ConfigChanged	374a3158-6dfa-41f2-9a4d-3d1091dffacf	human	\N	{"riskCategoryId": "22222222-2222-2222-2222-222222222222", "maxMitigationFactor": 0.85}	QA-FT 05Oct: restore Customers & Entities cap to 0.85 after TC-CFG-01	2026-10-05 09:39:05.383305+00
58d7cce5-5e35-4cda-b1b0-2b66aafa8753	\N	\N	WorkflowRule	10ffc9e2-e8ab-429e-8e5c-295066c6d3a7	ConfigChanged	374a3158-6dfa-41f2-9a4d-3d1091dffacf	human	\N	{"ruleKey": "CommitteeQuorum", "ruleValue": {"quorum": 3}}	QA-FT 05Oct TC-CFG-03: quorum 3 (restored to 2 after test)	2026-10-05 09:39:44.368898+00
31140df8-bff9-42db-a8cb-e51bca8621a2	\N	\N	WorkflowRule	b424413e-b0bf-4728-9ae3-0dd88395d1a8	ConfigChanged	374a3158-6dfa-41f2-9a4d-3d1091dffacf	human	\N	{"ruleKey": "CommitteeQuorum", "ruleValue": {"quorum": 2}}	QA-FT 05Oct: restore quorum to 2 after TC-CFG-03	2026-10-05 09:39:49.851603+00
5bf5bb68-2ccc-4886-a6dc-2db2da069b02	\N	\N	WorkflowRule	e4112056-e1d6-461c-be2d-654eb978e064	ConfigChanged	4fa322d3-2245-44ef-b664-1a804442db23	human	\N	{"ruleKey": "CommitteeQuorum", "ruleValue": {"quorum": 2}}	QA-FT TC-ACL-02: Analyst workflow save (must be refused)	2026-10-05 09:40:38.479899+00
fa4070c5-74c7-4d7d-b97f-cafc9eabf938	d926e791-83f0-4a97-bf81-27057c1c914b	\N	ChangeRequest	d926e791-83f0-4a97-bf81-27057c1c914b	Created	083ecfe5-aa01-4703-9168-762f0065078f	human	\N	{"title": "[QA-FT 05Oct] TC-ACL-02 committee member submit (must be refused)", "status": "Submitted", "changeType": "Process"}	\N	2026-10-05 09:40:38.901022+00
2de72432-d523-49cb-ba65-3abbde649be0	\N	386b9113-a53e-4b90-a396-35e574b2bfa3	CategoryMapping	ecfe53b8-fb9d-4433-afbb-b134775afd63	Overridden	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	{"id": "ecfe53b8-fb9d-4433-afbb-b134775afd63", "source": "AnalystAdded", "is_active": true, "created_at": "2026-10-05T09:17:39.703211+00:00", "ai_citation": null, "assessment_id": "386b9113-a53e-4b90-a396-35e574b2bfa3", "risk_category_id": "22222222-2222-2222-2222-222222222224", "created_by_user_id": "4fa322d3-2245-44ef-b664-1a804442db23"}	{"isActive": true, "riskCategoryId": "22222222-2222-2222-2222-222222222224"}	QA-FT TC-ACL-02: Product Owner analyst action (must be refused)	2026-10-05 09:40:39.313168+00
43671345-6acb-4d47-a15d-3911285b942d	3f0eaf26-cf7d-4bb3-921c-162f6ae43a3d	\N	ChangeRequest	3f0eaf26-cf7d-4bb3-921c-162f6ae43a3d	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-FT 05Oct XSS] <script>window.__xss=1</script><img src=x onerror=\\"window.__xss=2\\">", "status": "Submitted", "changeType": "Feature"}	\N	2026-10-05 09:41:34.457532+00
f46a7598-236c-43e5-9d56-27c93360464d	14f9fd2e-6c57-4b13-80ad-2358f79aef97	\N	ChangeRequest	14f9fd2e-6c57-4b13-80ad-2358f79aef97	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-FT 05Oct] Mobile submit (TC-CMP-01)", "status": "Submitted", "changeType": "Process"}	\N	2026-10-05 09:47:40.67464+00
3973e47c-739e-4bc0-a2f1-f7d08f7f6e00	4fe145bd-924b-4d09-83c4-3d9b3981a88d	\N	ChangeRequest	4fe145bd-924b-4d09-83c4-3d9b3981a88d	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-FT 05Oct] edge compatibility submit (TC-CMP-01)", "status": "Submitted", "changeType": "Process"}	\N	2026-10-05 09:48:41.101586+00
2d91c9e9-d065-46d5-9704-1bb1eb0ab282	1db33cf3-d01d-4b60-8466-20fce8524875	\N	ChangeRequest	1db33cf3-d01d-4b60-8466-20fce8524875	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "[QA-FT 05Oct] firefox compatibility submit (TC-CMP-01)", "status": "Submitted", "changeType": "Process"}	\N	2026-10-05 09:58:29.31736+00
7d74ee3a-4a66-4e18-96f3-f2c635e6ac84	\N	\N	SlaConfig	8a75bac7-b9ba-4928-a791-97e0ccefa082	ConfigChanged	374a3158-6dfa-41f2-9a4d-3d1091dffacf	human	{"targets": [{"stage": "EndToEnd", "changeType": "CustomerSegment", "targetBusinessDays": 15}, {"stage": "InAssessment", "changeType": "CustomerSegment", "targetBusinessDays": 8}, {"stage": "PendingCommittee", "changeType": "CustomerSegment", "targetBusinessDays": 5}, {"stage": "Submitted", "changeType": "CustomerSegment", "targetBusinessDays": 2}, {"stage": "EndToEnd", "changeType": "Feature", "targetBusinessDays": 15}, {"stage": "InAssessment", "changeType": "Feature", "targetBusinessDays": 8}, {"stage": "PendingCommittee", "changeType": "Feature", "targetBusinessDays": 5}, {"stage": "Submitted", "changeType": "Feature", "targetBusinessDays": 2}, {"stage": "EndToEnd", "changeType": "Geography", "targetBusinessDays": 15}, {"stage": "InAssessment", "changeType": "Geography", "targetBusinessDays": 8}, {"stage": "PendingCommittee", "changeType": "Geography", "targetBusinessDays": 5}, {"stage": "Submitted", "changeType": "Geography", "targetBusinessDays": 2}, {"stage": "EndToEnd", "changeType": "Process", "targetBusinessDays": 15}, {"stage": "InAssessment", "changeType": "Process", "targetBusinessDays": 8}, {"stage": "PendingCommittee", "changeType": "Process", "targetBusinessDays": 5}, {"stage": "Submitted", "changeType": "Process", "targetBusinessDays": 2}, {"stage": "EndToEnd", "changeType": "Product", "targetBusinessDays": 15}, {"stage": "InAssessment", "changeType": "Product", "targetBusinessDays": 8}, {"stage": "PendingCommittee", "changeType": "Product", "targetBusinessDays": 5}, {"stage": "Submitted", "changeType": "Product", "targetBusinessDays": 2}, {"stage": "EndToEnd", "changeType": "Vendor", "targetBusinessDays": 15}, {"stage": "InAssessment", "changeType": "Vendor", "targetBusinessDays": 8}, {"stage": "PendingCommittee", "changeType": "Vendor", "targetBusinessDays": 5}, {"stage": "Submitted", "changeType": "Vendor", "targetBusinessDays": 2}], "version": 1, "atRiskThresholdPct": 80, "pauseOnClarification": true}	{"targets": [{"stage": "EndToEnd", "changeType": "Product", "targetBusinessDays": 2}, {"stage": "EndToEnd", "changeType": "Feature", "targetBusinessDays": 2}, {"stage": "EndToEnd", "changeType": "Process", "targetBusinessDays": 2}, {"stage": "EndToEnd", "changeType": "Vendor", "targetBusinessDays": 2}, {"stage": "EndToEnd", "changeType": "Geography", "targetBusinessDays": 2}, {"stage": "EndToEnd", "changeType": "CustomerSegment", "targetBusinessDays": 2}], "version": 2, "retroactive": false, "atRiskThresholdPct": 80, "pauseOnClarification": true}	Aligned to the 2-business-day decision target agreed on the 7 Oct 2026 sync-up (overall only, stage targets optional)	2026-10-07 14:06:49.635771+00
41799014-94a5-429d-8af4-4e6b7ad95592	90acf576-4272-4b63-bf8c-b55461910c28	\N	ChangeRequest	90acf576-4272-4b63-bf8c-b55461910c28	Created	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	human	\N	{"title": "SLA two-day check", "status": "Submitted", "changeType": "Process"}	\N	2026-10-07 14:07:05.667423+00
\.


--
-- Data for Name: change_request; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.change_request (id, request_number, change_type, title, description, type_specific_fields, status, submitted_by_user_id, submitted_at, created_at) FROM stdin;
8400daf2-14ec-489a-878f-2053e67a1d31	CR-2026-00001	Process	Azure DB e2e verification test	Confirming write path works end-to-end against pgsql-gh-dev-01 after switching local dev off Docker Postgres.	{}	InAssessment	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-22 14:13:48.366072+00	2026-09-22 14:13:48.366072+00
c73e1706-d774-4fb7-9a86-95f260c31f2b	CR-2026-00032	Geography	[QA-E2E 202609250649] clarification	x	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:50:17.709215+00	2026-09-25 06:50:17.709215+00
a0c484e3-fdc0-4275-bbee-51fec3c0f04d	CR-2026-00033	Product	[QA-E2E 202609250649] snapshot linked	x	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:50:19.236347+00	2026-09-25 06:50:19.236347+00
87057aee-66d0-4eed-b503-ee593be28113	CR-2026-00002	Vendor	Onboard QuickPay Processing for card settlement	QuickPay Processing LLC will process full transaction data and card PANs for our new prepaid settlement flow. Cayman Islands jurisdiction, currently no compliance certification on file.	{"vendorName": "QuickPay Processing LLC", "jurisdiction": "Cayman Islands", "dataAccessScope": "Full transaction data, card PANs"}	Decisioned	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-22 15:32:14.491609+00	2026-09-22 15:32:14.491609+00
40affe4d-9ba8-48a6-b354-d60668956ac6	CR-2026-00034	Process	[QA-E2E 202609250649] snapshot none	x	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:50:19.597754+00	2026-09-25 06:50:19.597754+00
9fd8d7bc-d6d7-4e7a-912f-f375ddd98a6c	CR-2026-00035	Vendor	[QA-E2E probe] versioning	x	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:50:40.560319+00	2026-09-25 06:50:40.560319+00
bd7b9737-77c8-4564-8a78-2d64ba3060a3	CR-2026-00004	Product	AzureFoundry E2E Test - Prepaid Card Launch	Testing the AzureFoundry AI provider end-to-end via category mapping propose call, after switching AI_PROVIDER back to AzureFoundry locally.	{}	Decisioned	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-24 17:19:42.292795+00	2026-09-24 17:19:42.292795+00
fd8253fb-6283-4e71-9b9c-53bf0ca1790f	CR-2026-00005	Product	[QA-E2E 202609250649] API intake - prepaid card	Synthetic QA request	{"details": "US only"}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:49:22.047018+00	2026-09-25 06:49:22.047018+00
7613c46e-1aa4-4260-8027-22e0114d760d	CR-2026-00006	Product	[QA-E2E 202609250649] type Product	Synthetic	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:49:22.990982+00	2026-09-25 06:49:22.990982+00
52b609f3-3f61-4b2e-9bfa-0e215555b5d5	CR-2026-00007	Feature	[QA-E2E 202609250649] type Feature	Synthetic	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:49:23.278225+00	2026-09-25 06:49:23.278225+00
09a5036e-ad3f-48ff-b2cf-fce2b8ada8e4	CR-2026-00008	Process	[QA-E2E 202609250649] type Process	Synthetic	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:49:23.566589+00	2026-09-25 06:49:23.566589+00
1d6e0018-0dbe-4b67-b4ae-eb80a828c493	CR-2026-00009	Vendor	[QA-E2E 202609250649] type Vendor	Synthetic	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:49:23.85048+00	2026-09-25 06:49:23.85048+00
8d3e5920-b652-492a-8bfc-a267db3389d6	CR-2026-00010	Geography	[QA-E2E 202609250649] type Geography	Synthetic	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:49:24.134701+00	2026-09-25 06:49:24.134701+00
5bcb3b1d-d7cc-41a7-8d39-277aa7a76694	CR-2026-00011	CustomerSegment	[QA-E2E 202609250649] type CustomerSegment	Synthetic	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:49:24.411171+00	2026-09-25 06:49:24.411171+00
5de8ab3f-5c62-4f6a-a40b-360a6cabd8d1	CR-2026-00012	Product			{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:49:26.117233+00	2026-09-25 06:49:26.117233+00
6dbe79eb-3aec-4d08-bcbf-f06873955cd1	CR-2026-00015	Vendor	[QA-E2E 202609250649] attachments	x	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:49:33.021022+00	2026-09-25 06:49:33.021022+00
caef4c84-30cc-40b5-9675-492cab0ee7a6	CR-2026-00016	Vendor	[QA-E2E 202609250649] bad uploads	x	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:49:37.716834+00	2026-09-25 06:49:37.716834+00
5c23a789-398d-4685-bbf6-f4977f7c9d6f	CR-2026-00017	Geography	[QA-E2E 202609250649] clarification	x	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:49:40.541984+00	2026-09-25 06:49:40.541984+00
e83eae48-d616-48ec-8947-e81e3bc4e0f3	CR-2026-00018	Product	[QA-E2E 202609250649] snapshot linked	x	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:49:42.043857+00	2026-09-25 06:49:42.043857+00
eee8de4f-c64c-436e-92b3-f9c85e7b3d91	CR-2026-00019	Process	[QA-E2E 202609250649] snapshot none	x	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:49:42.405273+00	2026-09-25 06:49:42.405273+00
97305b4b-fdb8-418c-9987-3cfafcd1d1dd	CR-2026-00020	Product	[QA-E2E 202609250649] API intake - prepaid card	Synthetic QA request	{"details": "US only"}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:50:00.31761+00	2026-09-25 06:50:00.31761+00
99fe5bab-2439-4d0e-8be6-20e5656ad100	CR-2026-00021	Product	[QA-E2E 202609250649] type Product	Synthetic	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:50:01.319542+00	2026-09-25 06:50:01.319542+00
24611c0a-41dc-4d53-a30d-d6b4b4cc1678	CR-2026-00023	Process	[QA-E2E 202609250649] type Process	Synthetic	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:50:01.925024+00	2026-09-25 06:50:01.925024+00
b6547a00-7b54-49b6-b57f-7bef8b75019e	CR-2026-00024	Vendor	[QA-E2E 202609250649] type Vendor	Synthetic	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:50:02.225653+00	2026-09-25 06:50:02.225653+00
cff8bed1-7fce-4d6e-a0bf-b23161306c4e	CR-2026-00025	Geography	[QA-E2E 202609250649] type Geography	Synthetic	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:50:02.519935+00	2026-09-25 06:50:02.519935+00
1083ff18-0335-423f-9ae8-a735fe833302	CR-2026-00026	CustomerSegment	[QA-E2E 202609250649] type CustomerSegment	Synthetic	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:50:02.805663+00	2026-09-25 06:50:02.805663+00
506888b7-0548-4f31-91fc-8ee9d999bad0	CR-2026-00027	Product			{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:50:04.552981+00	2026-09-25 06:50:04.552981+00
3976f8cd-9fce-4858-b550-2ba02670603c	CR-2026-00030	Vendor	[QA-E2E 202609250649] attachments	x	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:50:11.579863+00	2026-09-25 06:50:11.579863+00
b5e1065a-a458-4f71-a672-0d3a516a4578	CR-2026-00031	Vendor	[QA-E2E 202609250649] bad uploads	x	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:50:14.895356+00	2026-09-25 06:50:14.895356+00
89313b30-9064-4caa-8838-29e42ddc72f2	CR-2026-00036	Vendor	[QA-E2E 202609250653] API lifecycle - onboard settlement vendor	Onboard a Malta-based card settlement processor with access to cardholder PII.	{"details": "Vendor: QuickPay; jurisdiction: Malta; data access: cardholder PII"}	Decisioned	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:53:46.849586+00	2026-09-25 06:53:46.849586+00
d80b9214-6103-4950-bbbf-e2ed93d18531	CR-2026-00039	Feature	[QA-E2E 202609250658] API probe - re-vote	x	{}	PendingCommittee	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:59:45.884143+00	2026-09-25 06:59:45.884143+00
298d4e01-a257-407a-9f27-04b96c02ff54	CR-2026-00037	Vendor	[QA-E2E 202609250658] API lifecycle - onboard settlement vendor	Onboard a Malta-based card settlement processor with access to cardholder PII.	{"details": "Vendor: QuickPay; jurisdiction: Malta; data access: cardholder PII"}	Decisioned	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:58:38.557773+00	2026-09-25 06:58:38.557773+00
9782168a-6d7f-479a-ae0a-ca201f728af2	CR-2026-00041	Process	[QA-E2E 202609250702] API probe - actor spoofing	x	{}	InAssessment	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 07:02:31.665139+00	2026-09-25 07:02:31.665139+00
83f2c245-439e-4b8a-8206-ee1bda436d80	CR-2026-00038	Feature	[QA-E2E 202609250658] API probe - empty assessment	Nothing will be reviewed on this one	{}	Decisioned	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:58:40.934675+00	2026-09-25 06:58:40.934675+00
aff5b2e9-5ae7-4adf-8bf8-23de8bdca397	CR-2026-00040	CustomerSegment	[QA-E2E 202609250702] API probe - config versioning	x	{}	InAssessment	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 07:02:20.810607+00	2026-09-25 07:02:20.810607+00
fdde906d-fee7-4abe-ab0a-3372b4e0f9b5	CR-2026-00042	Feature	[QA-E2E 202609250702] long AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA	x	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 07:02:47.355479+00	2026-09-25 07:02:47.355479+00
9c73424d-30b2-4a3e-8881-c25af94572ba	CR-2026-00043	Vendor	[QA-E2E 202609250707] UI lifecycle - onboard Malta settlement vendor	Onboard QuickPay Processing Ltd (Malta) as card settlement processor; it will receive cardholder PII and settlement files over an API.	{"details": "Vendor: QuickPay Processing Ltd; jurisdiction: Malta; data access scope: cardholder PII"}	InAssessment	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 07:08:16.035539+00	2026-09-25 07:08:16.035539+00
a4614f58-6f4f-45bf-92fb-1d652866657e	CR-2026-00044	Feature	[QA-E2E 202609250720] <img src=x onerror="window.__xss=1"><script>window.__xss=2</script>	<img src=x onerror="window.__xss=1"><script>window.__xss=2</script>	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 07:20:20.08475+00	2026-09-25 07:20:20.08475+00
7e97dfcc-50bd-40a8-b0cb-5db666f40111	CR-2026-00045	Product	[QA-E2E FINAL09251251] API intake - prepaid card	Synthetic QA request	{"details": "US only"}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 07:21:58.094958+00	2026-09-25 07:21:58.094958+00
83fd772d-e35b-4f9c-9d75-c4064841e157	CR-2026-00046	Product	[QA-E2E FINAL09251251] type Product	Synthetic	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 07:21:59.081579+00	2026-09-25 07:21:59.081579+00
c2f156eb-e295-44e9-ad78-723a35feefb8	CR-2026-00047	Feature	[QA-E2E FINAL09251251] type Feature	Synthetic	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 07:21:59.387397+00	2026-09-25 07:21:59.387397+00
f0ce4db6-ca13-4f7c-a468-d6651c2e34be	CR-2026-00048	Process	[QA-E2E FINAL09251251] type Process	Synthetic	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 07:21:59.698513+00	2026-09-25 07:21:59.698513+00
efbde630-cc1f-4931-8635-0941776edec5	CR-2026-00049	Vendor	[QA-E2E FINAL09251251] type Vendor	Synthetic	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 07:21:59.987346+00	2026-09-25 07:21:59.987346+00
1574b600-6773-46a4-a30e-1f7664101fc1	CR-2026-00050	Geography	[QA-E2E FINAL09251251] type Geography	Synthetic	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 07:22:00.28372+00	2026-09-25 07:22:00.28372+00
be27434a-b46d-4f8c-8f97-790e413248f7	CR-2026-00051	CustomerSegment	[QA-E2E FINAL09251251] type CustomerSegment	Synthetic	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 07:22:00.584982+00	2026-09-25 07:22:00.584982+00
fc726513-8a52-42e1-a104-fcbf7d023ab2	CR-2026-00052	Product			{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 07:22:02.524814+00	2026-09-25 07:22:02.524814+00
9c895ced-c6aa-44af-a2f3-d7d96fb72c43	CR-2026-00055	Vendor	[QA-E2E FINAL09251251] attachments	x	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 07:22:10.907194+00	2026-09-25 07:22:10.907194+00
7a6ea15a-41be-4f29-9882-0921a6ffbe48	CR-2026-00056	Vendor	[QA-E2E FINAL09251251] bad uploads	x	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 07:22:14.640162+00	2026-09-25 07:22:14.640162+00
ba127540-de51-4e40-989e-29b7bb56ec57	CR-2026-00057	Geography	[QA-E2E FINAL09251251] clarification	x	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 07:22:17.418978+00	2026-09-25 07:22:17.418978+00
91d32e88-acb4-4f61-9053-e7ce06c9f89f	CR-2026-00058	Product	[QA-E2E FINAL09251251] snapshot linked	x	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 07:22:18.92203+00	2026-09-25 07:22:18.92203+00
6a78af14-7388-4b01-8352-68ebf57be9a6	CR-2026-00059	Process	[QA-E2E FINAL09251251] snapshot none	x	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 07:22:19.302835+00	2026-09-25 07:22:19.302835+00
89c78436-ebd6-41fc-bdc0-0c7c9807d8b8	CR-2026-00071	Process	[QA-E2E 202609280759] type Process	Synthetic	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-28 08:00:07.989647+00	2026-09-28 08:00:07.989647+00
0a731172-0bbb-4489-aec4-db7828dd5928	CR-2026-00072	Vendor	[QA-E2E 202609280759] type Vendor	Synthetic	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-28 08:00:08.327834+00	2026-09-28 08:00:08.327834+00
cc995f7a-83e3-493f-b12c-ab0f43097f3a	CR-2026-00073	Geography	[QA-E2E 202609280759] type Geography	Synthetic	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-28 08:00:08.659638+00	2026-09-28 08:00:08.659638+00
bea75b32-b4c1-45d7-8ec9-65598745cf4e	CR-2026-00074	CustomerSegment	[QA-E2E 202609280759] type CustomerSegment	Synthetic	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-28 08:00:08.986344+00	2026-09-28 08:00:08.986344+00
18404cb0-2e0b-4ef4-9a7d-b06fffe699f5	CR-2026-00061	Feature	[QA-E2E FINAL09251251] API probe - empty assessment	Nothing will be reviewed on this one	{}	Decisioned	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 07:22:23.309325+00	2026-09-25 07:22:23.309325+00
e61cc526-3149-4f64-ac51-03cf2d2612f6	CR-2026-00075	Product			{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-28 08:00:11.419736+00	2026-09-28 08:00:11.419736+00
b1c408c0-01d2-4d51-b5e9-20cb5fdfba0a	CR-2026-00062	Feature	[QA-E2E FINAL09251251] API probe - re-vote	x	{}	PendingCommittee	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 07:23:33.329633+00	2026-09-25 07:23:33.329633+00
ef797803-aaf9-4a7a-b7af-a86f6f010f9a	CR-2026-00060	Vendor	[QA-E2E FINAL09251251] API lifecycle - onboard settlement vendor	Onboard a Malta-based card settlement processor with access to cardholder PII.	{"details": "Vendor: QuickPay; jurisdiction: Malta; data access: cardholder PII"}	Decisioned	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 07:22:21.121384+00	2026-09-25 07:22:21.121384+00
de00fb95-f4e9-4c55-9d17-781709873552	CR-2026-00063	CustomerSegment	[QA-E2E FINAL09251251] API probe - config versioning	x	{}	InAssessment	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 07:23:47.43906+00	2026-09-25 07:23:47.43906+00
eee96cea-4f87-4d0d-95bd-565397ba8cea	CR-2026-00064	Process	[QA-E2E FINAL09251251] API probe - actor spoofing	x	{}	InAssessment	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 07:23:58.882002+00	2026-09-25 07:23:58.882002+00
0833e6e4-c347-4e8a-8be2-b3d3f722d1ab	CR-2026-00065	Feature	[QA-E2E FINAL09251251] long AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA	x	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 07:24:15.21347+00	2026-09-25 07:24:15.21347+00
a9d2beb0-3e2b-4931-bced-0f79150dac20	CR-2026-00078	Vendor	[QA-E2E 202609280759] attachments	x	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-28 08:00:21.218879+00	2026-09-28 08:00:21.218879+00
11f899a8-e66a-4572-915e-b077ecf43280	CR-2026-00079	Vendor	[QA-E2E 202609280759] bad uploads	x	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-28 08:00:26.619129+00	2026-09-28 08:00:26.619129+00
507e6f32-ab80-40db-81bd-5f641ef033a4	CR-2026-00066	Vendor	[QA-E2E FINAL09251251] UI lifecycle - onboard Malta settlement vendor	Onboard QuickPay Processing Ltd (Malta) as card settlement processor; it will receive cardholder PII and settlement files over an API.	{"details": "Vendor: QuickPay Processing Ltd; jurisdiction: Malta; data access scope: cardholder PII"}	Decisioned	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 07:25:29.009477+00	2026-09-25 07:25:29.009477+00
95c5cf1d-f648-489c-8391-20721104947f	CR-2026-00067	Feature	[QA-E2E FINAL09251251] <img src=x onerror="window.__xss=1"><script>window.__xss=2</script>	<img src=x onerror="window.__xss=1"><script>window.__xss=2</script>	{}	InAssessment	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 07:29:55.042837+00	2026-09-25 07:29:55.042837+00
2f3859fc-cf3f-44fe-88d3-9ab40b8585e4	CR-2026-00068	Product	[QA-E2E 202609280759] API intake - prepaid card	Synthetic QA request	{"details": "US only"}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-28 08:00:05.779798+00	2026-09-28 08:00:05.779798+00
55d227e6-ab38-4a7b-b2b2-271a6482b96b	CR-2026-00069	Product	[QA-E2E 202609280759] type Product	Synthetic	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-28 08:00:07.287832+00	2026-09-28 08:00:07.287832+00
4fd54ca9-b073-4733-94a5-4ab3e7b61c01	CR-2026-00070	Feature	[QA-E2E 202609280759] type Feature	Synthetic	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-28 08:00:07.65264+00	2026-09-28 08:00:07.65264+00
62d2e0eb-c313-408c-b0b1-70ffe1196565	CR-2026-00080	Geography	[QA-E2E 202609280759] clarification	x	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-28 08:00:29.977655+00	2026-09-28 08:00:29.977655+00
8dce6573-54e9-41c3-a3f0-9b615351582d	CR-2026-00081	Product	[QA-E2E 202609280759] snapshot linked	x	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-28 08:00:31.521582+00	2026-09-28 08:00:31.521582+00
7f4b8f70-f2cc-4aca-890a-876a16f9860a	CR-2026-00082	Process	[QA-E2E 202609280759] snapshot none	x	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-28 08:00:31.903104+00	2026-09-28 08:00:31.903104+00
617f16d3-e50b-487c-a31d-cedbbc7b572a	CR-2026-00083	Vendor	[QA-E2E 202609280759] API lifecycle - onboard settlement vendor	Onboard a Malta-based card settlement processor with access to cardholder PII.	{"details": "Vendor: QuickPay; jurisdiction: Malta; data access: cardholder PII"}	Decisioned	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-28 08:00:33.744622+00	2026-09-28 08:00:33.744622+00
a3e3e745-edef-45d1-a62f-c20dbb048de0	CR-2026-00086	CustomerSegment	[QA-E2E 202609280759] API probe - config versioning	x	{}	InAssessment	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-28 08:02:14.349673+00	2026-09-28 08:02:14.349673+00
b3976f2e-4b74-4091-9aea-66af92b07bc5	CR-2026-00090	Feature	[QA-E2E 202609280759] <img src=x onerror="window.__xss=1"><script>window.__xss=2</script>	<img src=x onerror="window.__xss=1"><script>window.__xss=2</script>	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-28 08:08:38.758915+00	2026-09-28 08:08:38.758915+00
540ffca2-0e67-4ed9-9e72-39e1aa12152d	CR-2026-00084	Feature	[QA-E2E 202609280759] API probe - empty assessment	Nothing will be reviewed on this one	{}	Decisioned	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-28 08:00:35.897563+00	2026-09-28 08:00:35.897563+00
2afd7b9b-a899-466e-82e2-e58da781599a	CR-2026-00085	Feature	[QA-E2E 202609280759] API probe - re-vote	x	{}	PendingCommittee	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-28 08:01:58.467666+00	2026-09-28 08:01:58.467666+00
e7983599-9aee-492c-8444-8764ae4892d9	CR-2026-00087	Process	[QA-E2E 202609280759] API probe - actor spoofing	x	{}	InAssessment	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-28 08:02:27.812065+00	2026-09-28 08:02:27.812065+00
663e4342-4b4a-43ef-b6c2-a088ef3ce1cc	CR-2026-00088	Feature	[QA-E2E 202609280759] long AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA	x	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-28 08:02:44.593376+00	2026-09-28 08:02:44.593376+00
a6bbfac6-7b11-45b5-8c48-74c1efc1a343	CR-2026-00089	Vendor	[QA-E2E 202609280759] UI lifecycle - onboard Malta settlement vendor	Onboard QuickPay Processing Ltd (Malta) as card settlement processor; it will receive cardholder PII and settlement files over an API.	{"details": "Vendor: QuickPay Processing Ltd; jurisdiction: Malta; data access scope: cardholder PII"}	Decisioned	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-28 08:04:26.91279+00	2026-09-28 08:04:26.91279+00
455cb36d-c05b-46f3-bba4-2769c127a7d3	CR-2026-00091	Feature	test	test	{"details": "vendor test"}	PendingCommittee	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-28 08:26:01.922924+00	2026-09-28 08:26:01.922924+00
f278bcec-0b6e-4cad-a299-3cf307eb2a01	TEST-E2E-SHARED-1	Product	e2e shared test	test	{}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-29 08:13:52.443819+00	2026-09-29 08:13:52.443819+00
ac11f587-ee4f-40e6-a72f-e7e8f6be308a	TEST-E2E-SHARED-2	Product	e2e shared test B	test	{}	Decisioned	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-29 08:14:44.386983+00	2026-09-29 08:14:44.386983+00
823b48e6-5235-4fdf-9aa9-17ceb9417cd5	CR-2026-00094	Product	Deployed AI verify	Testing Anthropic workspace-scoped call on the deployed dev environment.	{}	InAssessment	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-29 11:04:30.15356+00	2026-09-29 11:04:30.15356+00
7a379245-0ee3-414a-884d-de47fc4ae358	CR-2026-00092	Vendor	[QA-E2E 202609280838] Onboard QuickPay Processing Ltd (Malta) as the card settlement processor for the consumer debit and prepaid card programmes, including cardholder PII and daily settlement file exchange over API	Exploratory UX check: long request title.	{"details": "Vendor: QuickPay Processing Ltd; jurisdiction: Malta"}	Decisioned	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-28 08:39:13.123812+00	2026-09-28 08:39:13.123812+00
724a96ec-6d75-4ebd-9ed5-d15d7abcccca	CR-2026-00022	Feature	[QA-E2E 202609250649] type Feature	Synthetic	{}	InAssessment	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:50:01.625912+00	2026-09-25 06:50:01.625912+00
1db33cf3-d01d-4b60-8466-20fce8524875	CR-2026-00105	Process	[QA-FT 05Oct] firefox compatibility submit (TC-CMP-01)	Submitted from firefox.	{"details": ""}	InAssessment	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-10-05 09:58:29.31736+00	2026-10-05 09:58:29.31736+00
846abe95-3e9a-438f-9b30-0c7097371a27	CR-2026-00096	Product	Launch Prepaid Settlement Card	New reloadable prepaid debit card for retail and small-business customers, with domestic and cross-border POS/ATM transactions.	{"details": "Card processing via third-party processor (QuickPay Processing Ltd); fully online onboarding, no branch visit required."}	PendingCommittee	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-30 11:15:53.3788+00	2026-09-30 11:15:53.3788+00
7a6b4b58-4a23-4844-8c3b-fd20377a720f	CR-2026-00095	Product	New Product by Suleman	New Product by Suleman	{"details": "New Product by Suleman"}	InAssessment	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-30 11:03:38.559476+00	2026-09-30 11:03:38.559476+00
d92baa78-c3dc-4ea5-ac3f-89b79959397d	CR-2026-00097	Vendor	[QA-FT 05Oct] Onboard QuickPay Processing as card settlement vendor	Onboard QuickPay Processing LLC (Malta) as card settlement processor. Vendor will receive cardholder PII and settlement files via API.	{"vendorName": "QuickPay Processing LLC", "jurisdiction": "Malta", "dataAccessScope": "Cardholder PII, settlement files"}	InAssessment	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-10-05 09:11:38.107328+00	2026-10-05 09:11:38.107328+00
bf57f2fb-8d22-4567-a0d3-6eed60680461	CR-2026-00099	Vendor	[QA-FT 05Oct] Onboard new vendor Aurora Ledger Ltd (not in VMS)	New vendor not yet in Vendor Management; details entered directly.	{"vendorName": "Aurora Ledger Ltd", "jurisdiction": "Cyprus", "dataAccessScope": "Transaction ledger exports"}	InAssessment	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-10-05 09:13:31.147194+00	2026-10-05 09:13:31.147194+00
a7ae047c-a52c-40dd-a9d6-7840e8e7a87a	CR-2026-00100	Vendor	[QA-FT 05Oct] Stale vendor id (TC-MCK-02)	Linked vendor id that does not exist in Vendor Management	{"vendorName": "Ghost Vendor", "jurisdiction": "Nowhere", "dataAccessScope": "None"}	InAssessment	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-10-05 09:36:23.377083+00	2026-10-05 09:36:23.377083+00
1676366d-3ee4-4d55-993d-afcd3dc38b9a	CR-2026-00098	Process	[QA-FT 05Oct] Move KYC refresh to online self-service	Process change: periodic KYC refresh for retail customers moves from branch to online non-face-to-face channel.	{"details": "Branch to online; affects retail KYC refresh"}	InAssessment	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-10-05 09:13:19.771242+00	2026-10-05 09:13:19.771242+00
d926e791-83f0-4a97-bf81-27057c1c914b	CR-2026-00101	Process	[QA-FT 05Oct] TC-ACL-02 committee member submit (must be refused)	role probe	{}	Submitted	083ecfe5-aa01-4703-9168-762f0065078f	2026-10-05 09:40:38.901022+00	2026-10-05 09:40:38.901022+00
3f0eaf26-cf7d-4bb3-921c-162f6ae43a3d	CR-2026-00102	Feature	[QA-FT 05Oct XSS] <script>window.__xss=1</script><img src=x onerror="window.__xss=2">	<b onmouseover="window.__xss=3">bold?</b> <svg onload="window.__xss=4"></svg>	{"details": ""}	InAssessment	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-10-05 09:41:34.457532+00	2026-10-05 09:41:34.457532+00
14f9fd2e-6c57-4b13-80ad-2358f79aef97	CR-2026-00103	Process	[QA-FT 05Oct] Mobile submit (TC-CMP-01)	Submitted from a 412px phone-sized viewport.	{"details": ""}	Submitted	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-10-05 09:47:40.67464+00	2026-10-05 09:47:40.67464+00
4fe145bd-924b-4d09-83c4-3d9b3981a88d	CR-2026-00104	Process	[QA-FT 05Oct] edge compatibility submit (TC-CMP-01)	Submitted from edge.	{"details": ""}	InAssessment	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-10-05 09:48:41.101586+00	2026-10-05 09:48:41.101586+00
90acf576-4272-4b63-bf8c-b55461910c28	CR-2026-00106	Process	SLA two-day check	d	{}	InAssessment	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-10-07 14:07:05.667423+00	2026-10-07 14:07:05.667423+00
\.


--
-- Data for Name: change_request_attachment; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.change_request_attachment (id, change_request_id, file_name, content_type, storage_path, extracted_text, version_number, superseded_by_attachment_id, uploaded_by_user_id, uploaded_at) FROM stdin;
4e2ef96e-3461-4035-8db2-901f5a0a11e0	8400daf2-14ec-489a-878f-2053e67a1d31	blob-test.docx	application/vnd.openxmlformats-officedocument.wordprocessingml.document	https://stghdev01.blob.core.windows.net/change-request-attachments/e51cf6bf-1ce8-4dfe-ae69-6c5c67f9aa5e-blob-test.docx	Vendor Onboarding SummaryVendor: Northbridge Document ServicesJurisdiction: CanadaData access scope: Scanned onboarding documents onlyCertification status: Certified	1	\N	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-22 14:57:54.098265+00
d0e2c4f6-3ecf-4088-bc65-aa0eb0ee5528	87057aee-66d0-4eed-b503-ee593be28113	quickpay-vendor-dd.docx	application/vnd.openxmlformats-officedocument.wordprocessingml.document	https://stghdev01.blob.core.windows.net/change-request-attachments/e2ce1802-a5a1-4e3f-9570-044eefe2ef2d-quickpay-vendor-dd.docx	Vendor Due Diligence SummaryVendor: QuickPay Processing LLCJurisdiction: Cayman IslandsData access scope: Full transaction data, card PANsCertification status: None on file - certification pendingNotes: Vendor processes card settlement data for the new prepaid product line. No SOC 2 or ISO 27001 certification currently on record.	1	\N	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-22 15:34:14.18654+00
56c30397-333c-4693-a798-f08a2721791b	6dbe79eb-3aec-4d08-bcbf-f06873955cd1	vendor-due-diligence.pdf	application/pdf	https://stghdev01.blob.core.windows.net/change-request-attachments/d9b532c6-47d8-4306-90a5-daa384211a90-vendor-due-diligence.pdf	QA-E2E Vendor Due Diligence Summary. Vendor name: QuickPay Processing Ltd. Jurisdiction: Malta. Data access scope: cardholder PII and settlement files. Customer types affected: retail cardholders, MSB merchants. Delivery channel: API, non-face-to-face.	1	\N	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:49:34.619423+00
544b1759-8ec1-4a12-80ec-08978ea9f20c	6dbe79eb-3aec-4d08-bcbf-f06873955cd1	product-spec.docx	application/vnd.openxmlformats-officedocument.wordprocessingml.document	https://stghdev01.blob.core.windows.net/change-request-attachments/c9a20dca-25f3-4806-9809-9c4ecc0c3a3c-product-spec.docx	QA-E2E Vendor Due Diligence Summary. Vendor name: QuickPay Processing Ltd. Jurisdiction: Malta. Data access scope: cardholder PII and settlement files. Customer types affected: retail cardholders, MSB merchants. Delivery channel: API, non-face-to-face.	1	\N	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:49:35.09969+00
15321c25-11f0-4134-a4e3-bdbe3667ce2c	6dbe79eb-3aec-4d08-bcbf-f06873955cd1	control-matrix.xlsx	application/vnd.openxmlformats-officedocument.spreadsheetml.sheet	https://stghdev01.blob.core.windows.net/change-request-attachments/63c8362b-ad53-46ef-ae6d-824ef9ed2bce-control-matrix.xlsx	0.8	1	\N	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:49:35.45411+00
32bc8dd4-c804-460c-8a28-12a231e13ee3	caef4c84-30cc-40b5-9675-492cab0ee7a6	malicious.exe	application/pdf	https://stghdev01.blob.core.windows.net/change-request-attachments/6708db95-bea8-4ffb-a642-2ed5b826b43e-malicious.exe	\N	1	\N	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:49:38.556232+00
bd88ab9c-2738-4d43-8286-6327845a2487	3976f8cd-9fce-4858-b550-2ba02670603c	vendor-due-diligence.pdf	application/pdf	https://stghdev01.blob.core.windows.net/change-request-attachments/03fcd81e-28ee-4d3a-949d-e2dd7ef8c250-vendor-due-diligence.pdf	QA-E2E Vendor Due Diligence Summary. Vendor name: QuickPay Processing Ltd. Jurisdiction: Malta. Data access scope: cardholder PII and settlement files. Customer types affected: retail cardholders, MSB merchants. Delivery channel: API, non-face-to-face.	1	\N	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:50:11.937225+00
268823cf-622d-4280-b349-f5d2d6534dc7	3976f8cd-9fce-4858-b550-2ba02670603c	product-spec.docx	application/vnd.openxmlformats-officedocument.wordprocessingml.document	https://stghdev01.blob.core.windows.net/change-request-attachments/f1afbf29-dacc-4cb0-90eb-2a72d00a351b-product-spec.docx	QA-E2E Vendor Due Diligence Summary. Vendor name: QuickPay Processing Ltd. Jurisdiction: Malta. Data access scope: cardholder PII and settlement files. Customer types affected: retail cardholders, MSB merchants. Delivery channel: API, non-face-to-face.	1	\N	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:50:12.283236+00
f615d44c-1079-495e-93d7-b65e2178c38f	3976f8cd-9fce-4858-b550-2ba02670603c	control-matrix.xlsx	application/vnd.openxmlformats-officedocument.spreadsheetml.sheet	https://stghdev01.blob.core.windows.net/change-request-attachments/5a349123-0783-43bd-9d84-69767244f2fc-control-matrix.xlsx	0.8	1	\N	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:50:12.611676+00
f56475d8-fd35-4453-b1bb-657f94479756	b5e1065a-a458-4f71-a672-0d3a516a4578	malicious.exe	application/pdf	https://stghdev01.blob.core.windows.net/change-request-attachments/e6893e0b-3468-4598-bf25-5651aa8ff0ec-malicious.exe	\N	1	\N	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:50:15.750002+00
c78afb44-6472-4fb8-8cae-e5ad15f7f27f	9fd8d7bc-d6d7-4e7a-912f-f375ddd98a6c	a.pdf	application/pdf	x/a.pdf	\N	1	\N	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:50:41.634989+00
3ee6c57f-3dac-43a8-b682-850e1711ce46	9fd8d7bc-d6d7-4e7a-912f-f375ddd98a6c	vendor-due-diligence.pdf	application/pdf	https://stghdev01.blob.core.windows.net/change-request-attachments/ac280772-dde4-4ba1-9c96-b77f00d4dd72-vendor-due-diligence.pdf	QA-E2E Vendor Due Diligence Summary. Vendor name: QuickPay Processing Ltd. Jurisdiction: Malta. Data access scope: cardholder PII and settlement files. Customer types affected: retail cardholders, MSB merchants. Delivery channel: API, non-face-to-face.	1	\N	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:50:44.516777+00
7ccdf7d2-288f-4a80-833f-4720064f1d5f	89313b30-9064-4caa-8838-29e42ddc72f2	vendor-due-diligence.pdf	application/pdf	https://stghdev01.blob.core.windows.net/change-request-attachments/3978b733-4aab-4b37-822e-2fde968ab5f8-vendor-due-diligence.pdf	QA-E2E Vendor Due Diligence Summary. Vendor name: QuickPay Processing Ltd. Jurisdiction: Malta. Data access scope: cardholder PII and settlement files. Customer types affected: retail cardholders, MSB merchants. Delivery channel: API, non-face-to-face.	1	\N	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:53:47.313765+00
b95d8cc7-a14f-4176-b87a-56d9a8072f03	298d4e01-a257-407a-9f27-04b96c02ff54	vendor-due-diligence.pdf	application/pdf	https://stghdev01.blob.core.windows.net/change-request-attachments/6196cb52-c555-4450-b470-7aefd0bc0cd7-vendor-due-diligence.pdf	QA-E2E Vendor Due Diligence Summary. Vendor name: QuickPay Processing Ltd. Jurisdiction: Malta. Data access scope: cardholder PII and settlement files. Customer types affected: retail cardholders, MSB merchants. Delivery channel: API, non-face-to-face.	1	\N	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 06:58:39.046798+00
2f251d32-03d7-4e32-a46e-424f1afea090	9c73424d-30b2-4a3e-8881-c25af94572ba	vendor-due-diligence.pdf	application/pdf	https://stghdev01.blob.core.windows.net/change-request-attachments/56a136ad-c94d-47cd-8293-657810439a7f-vendor-due-diligence.pdf	QA-E2E Vendor Due Diligence Summary. Vendor name: QuickPay Processing Ltd. Jurisdiction: Malta. Data access scope: cardholder PII and settlement files. Customer types affected: retail cardholders, MSB merchants. Delivery channel: API, non-face-to-face.	1	\N	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 07:08:21.902721+00
e2fa7fd3-44bd-4b37-8f6c-63786c9ed9e6	9c73424d-30b2-4a3e-8881-c25af94572ba	product-spec.docx	application/vnd.openxmlformats-officedocument.wordprocessingml.document	https://stghdev01.blob.core.windows.net/change-request-attachments/63809419-fabe-4039-a51d-79d6c666df13-product-spec.docx	QA-E2E Vendor Due Diligence Summary. Vendor name: QuickPay Processing Ltd. Jurisdiction: Malta. Data access scope: cardholder PII and settlement files. Customer types affected: retail cardholders, MSB merchants. Delivery channel: API, non-face-to-face.	1	\N	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 07:08:26.93051+00
e1d426f2-d94c-4b66-8926-37b8cc387e76	9c73424d-30b2-4a3e-8881-c25af94572ba	control-matrix.xlsx	application/vnd.openxmlformats-officedocument.spreadsheetml.sheet	https://stghdev01.blob.core.windows.net/change-request-attachments/e9cd3590-8fae-496a-8ac0-2ea2cf87b8c8-control-matrix.xlsx	0.8	1	\N	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 07:08:32.342311+00
f707d937-1e2a-41ce-a4d8-f2d6a6843f03	9c895ced-c6aa-44af-a2f3-d7d96fb72c43	vendor-due-diligence.pdf	application/pdf	https://stghdev01.blob.core.windows.net/change-request-attachments/a76917d0-5f3a-4f7b-a5bd-6e44b569b94d-vendor-due-diligence.pdf	QA-E2E Vendor Due Diligence Summary. Vendor name: QuickPay Processing Ltd. Jurisdiction: Malta. Data access scope: cardholder PII and settlement files. Customer types affected: retail cardholders, MSB merchants. Delivery channel: API, non-face-to-face.	1	\N	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 07:22:11.282918+00
f1644753-11c1-4cf8-bad3-cd758f6ca7f1	9c895ced-c6aa-44af-a2f3-d7d96fb72c43	product-spec.docx	application/vnd.openxmlformats-officedocument.wordprocessingml.document	https://stghdev01.blob.core.windows.net/change-request-attachments/43c9cf0c-09a7-4807-94b1-b7fd7bf21b68-product-spec.docx	QA-E2E Vendor Due Diligence Summary. Vendor name: QuickPay Processing Ltd. Jurisdiction: Malta. Data access scope: cardholder PII and settlement files. Customer types affected: retail cardholders, MSB merchants. Delivery channel: API, non-face-to-face.	1	\N	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 07:22:11.617289+00
72abff8e-2572-4136-b919-454bf79fbaae	9c895ced-c6aa-44af-a2f3-d7d96fb72c43	control-matrix.xlsx	application/vnd.openxmlformats-officedocument.spreadsheetml.sheet	https://stghdev01.blob.core.windows.net/change-request-attachments/77bbf2cd-a48a-488a-b3cc-312b7d58f732-control-matrix.xlsx	0.8	1	\N	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 07:22:11.924679+00
6aaa2f77-6005-46ec-a4ed-4b47a76a5d83	7a6ea15a-41be-4f29-9882-0921a6ffbe48	malicious.exe	application/pdf	https://stghdev01.blob.core.windows.net/change-request-attachments/f31b5dd4-aecf-4a72-8dda-91705c4cdca3-malicious.exe	\N	1	\N	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 07:22:15.487132+00
bec64b5e-fcf3-4dfb-9805-490a757c5a5c	ef797803-aaf9-4a7a-b7af-a86f6f010f9a	vendor-due-diligence.pdf	application/pdf	https://stghdev01.blob.core.windows.net/change-request-attachments/f16857b4-c488-4f2a-ba2e-e30013a56360-vendor-due-diligence.pdf	QA-E2E Vendor Due Diligence Summary. Vendor name: QuickPay Processing Ltd. Jurisdiction: Malta. Data access scope: cardholder PII and settlement files. Customer types affected: retail cardholders, MSB merchants. Delivery channel: API, non-face-to-face.	1	\N	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 07:22:21.523301+00
00081c88-4365-4838-a6c0-96bc9b7b5258	507e6f32-ab80-40db-81bd-5f641ef033a4	vendor-due-diligence.pdf	application/pdf	https://stghdev01.blob.core.windows.net/change-request-attachments/104be795-a1c4-4cb8-8580-92f5ecb6fedb-vendor-due-diligence.pdf	QA-E2E Vendor Due Diligence Summary. Vendor name: QuickPay Processing Ltd. Jurisdiction: Malta. Data access scope: cardholder PII and settlement files. Customer types affected: retail cardholders, MSB merchants. Delivery channel: API, non-face-to-face.	1	\N	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 07:25:34.395694+00
6dd3a474-8dce-4920-a29e-0f9f43cd72c7	507e6f32-ab80-40db-81bd-5f641ef033a4	product-spec.docx	application/vnd.openxmlformats-officedocument.wordprocessingml.document	https://stghdev01.blob.core.windows.net/change-request-attachments/57b93a48-24da-4edb-8e1a-81d6b6f98161-product-spec.docx	QA-E2E Vendor Due Diligence Summary. Vendor name: QuickPay Processing Ltd. Jurisdiction: Malta. Data access scope: cardholder PII and settlement files. Customer types affected: retail cardholders, MSB merchants. Delivery channel: API, non-face-to-face.	1	\N	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 07:25:39.878335+00
1cda1ab4-a509-4f5d-877a-0660fbc6e2fa	507e6f32-ab80-40db-81bd-5f641ef033a4	control-matrix.xlsx	application/vnd.openxmlformats-officedocument.spreadsheetml.sheet	https://stghdev01.blob.core.windows.net/change-request-attachments/faf63401-bc19-4ab2-8c57-eec4295a518b-control-matrix.xlsx	0.8	1	\N	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-25 07:25:44.902114+00
5ea19f44-100e-4c9f-8c13-716e8caf0afa	a9d2beb0-3e2b-4931-bced-0f79150dac20	vendor-due-diligence.pdf	application/pdf	https://stghdev01.blob.core.windows.net/change-request-attachments/5e864c6d-d5fa-4cf4-80b4-5b04ae0904e7-vendor-due-diligence.pdf	QA-E2E Vendor Due Diligence Summary. Vendor name: QuickPay Processing Ltd. Jurisdiction: Malta. Data access scope: cardholder PII and settlement files. Customer types affected: retail cardholders, MSB merchants. Delivery channel: API, non-face-to-face.	1	\N	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-28 08:00:22.525538+00
ea0c926c-5aa4-4d8d-ae76-97d8d19427da	a9d2beb0-3e2b-4931-bced-0f79150dac20	product-spec.docx	application/vnd.openxmlformats-officedocument.wordprocessingml.document	https://stghdev01.blob.core.windows.net/change-request-attachments/9ed85ea0-d0c4-4ab0-a047-49f3a7096721-product-spec.docx	QA-E2E Vendor Due Diligence Summary. Vendor name: QuickPay Processing Ltd. Jurisdiction: Malta. Data access scope: cardholder PII and settlement files. Customer types affected: retail cardholders, MSB merchants. Delivery channel: API, non-face-to-face.	1	\N	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-28 08:00:22.870235+00
3e2f310e-760d-4b58-9865-638b0e77c329	a9d2beb0-3e2b-4931-bced-0f79150dac20	control-matrix.xlsx	application/vnd.openxmlformats-officedocument.spreadsheetml.sheet	https://stghdev01.blob.core.windows.net/change-request-attachments/971910a4-fa47-4ca3-b0f5-7c1c5139f823-control-matrix.xlsx	0.8	1	\N	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-28 08:00:23.217589+00
f5d18095-5bf1-4eb0-9f1c-acf363fd2c69	11f899a8-e66a-4572-915e-b077ecf43280	malicious.exe	application/pdf	https://stghdev01.blob.core.windows.net/change-request-attachments/a41bb0b9-e3f7-418a-a597-8286756eb958-malicious.exe	\N	1	\N	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-28 08:00:27.441842+00
d9da15e7-6334-4e80-8024-90c0234ef226	617f16d3-e50b-487c-a31d-cedbbc7b572a	vendor-due-diligence.pdf	application/pdf	https://stghdev01.blob.core.windows.net/change-request-attachments/eac6f0b2-c3e1-43d7-be7b-43d942ee544e-vendor-due-diligence.pdf	QA-E2E Vendor Due Diligence Summary. Vendor name: QuickPay Processing Ltd. Jurisdiction: Malta. Data access scope: cardholder PII and settlement files. Customer types affected: retail cardholders, MSB merchants. Delivery channel: API, non-face-to-face.	1	\N	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-28 08:00:34.174284+00
f81b2017-2a58-4223-9909-bcf0f23738ba	a6bbfac6-7b11-45b5-8c48-74c1efc1a343	vendor-due-diligence.pdf	application/pdf	https://stghdev01.blob.core.windows.net/change-request-attachments/142613cb-863a-492d-83ff-e6a903fd0e73-vendor-due-diligence.pdf	QA-E2E Vendor Due Diligence Summary. Vendor name: QuickPay Processing Ltd. Jurisdiction: Malta. Data access scope: cardholder PII and settlement files. Customer types affected: retail cardholders, MSB merchants. Delivery channel: API, non-face-to-face.	1	\N	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-28 08:04:33.182421+00
5e353e31-d23f-4f9b-aa73-6e14170baa87	a6bbfac6-7b11-45b5-8c48-74c1efc1a343	product-spec.docx	application/vnd.openxmlformats-officedocument.wordprocessingml.document	https://stghdev01.blob.core.windows.net/change-request-attachments/a3d633a1-ef05-45a6-bc93-226aaff5522e-product-spec.docx	QA-E2E Vendor Due Diligence Summary. Vendor name: QuickPay Processing Ltd. Jurisdiction: Malta. Data access scope: cardholder PII and settlement files. Customer types affected: retail cardholders, MSB merchants. Delivery channel: API, non-face-to-face.	1	\N	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-28 08:04:38.404736+00
be3ee544-3fa1-453d-8c8f-e4b1b9e49f2c	a6bbfac6-7b11-45b5-8c48-74c1efc1a343	control-matrix.xlsx	application/vnd.openxmlformats-officedocument.spreadsheetml.sheet	https://stghdev01.blob.core.windows.net/change-request-attachments/90aef66c-f1b8-4dc2-815d-631e943cfb0d-control-matrix.xlsx	0.8	1	\N	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-28 08:04:43.766197+00
1a905a57-dc5c-4db6-aedd-3148fe13768d	ac11f587-ee4f-40e6-a72f-e7e8f6be308a	secret-b.pdf	application/pdf	blob://b	CONFIDENTIAL B	1	\N	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-29 08:14:44.386983+00
1fa4e0f7-3a28-443a-9401-ccb24a01184d	7a6b4b58-4a23-4844-8c3b-fd20377a720f	product-launch-brief.pdf	application/pdf	https://stghdev01.blob.core.windows.net/change-request-attachments/5e1f229c-7d59-4c79-9a23-23edd9231316-product-launch-brief.pdf	Product Launch Brief - Prepaid Settlement CardProduct: A reloadable prepaid debit card issued to retail and small-business customers,enabling domestic and cross-border point-of-sale and ATM transactions.Target customers: Retail consumers and cash-intensive small businesses (e.g. retailshops, restaurants). No PEP or NRA customers targeted at launch.Transaction types: Card-present point-of-sale, ATM withdrawal, and card-not-presentonline transactions. Cross-border transactions supported in 12 countries including twoFATF-monitored jurisdictions.Onboarding channel: Fully online (non-face-to-face) enrollment via mobile app; nobranch visit required.Third parties: Card processing handled by an external payment processor (QuickPayProcessing Ltd) with API-based daily settlement file exchange.Data handled: Cardholder PII (name, address, SSN last-4), transaction history, devicefingerprint.	1	\N	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-30 11:21:39.670473+00
17b2efa1-50d9-47e5-80af-b905522d548a	846abe95-3e9a-438f-9b30-0c7097371a27	product-launch-brief-Prepaid-Settlement-Card.pdf	application/pdf	https://stghdev01.blob.core.windows.net/change-request-attachments/2cc5a710-057d-476c-9d41-43002baa4c90-product-launch-brief-Prepaid-Settlement-Card.pdf	Product Launch Brief - Prepaid Settlement CardProduct: A reloadable prepaid debit card issued to retail and small-business customers,enabling domestic and cross-border point-of-sale and ATM transactions.Target customers: Retail consumers and cash-intensive small businesses (e.g. retailshops, restaurants). No PEP or NRA customers targeted at launch.Transaction types: Card-present point-of-sale, ATM withdrawal, and card-not-presentonline transactions. Cross-border transactions supported in 12 countries including twoFATF-monitored jurisdictions.Onboarding channel: Fully online (non-face-to-face) enrollment via mobile app; nobranch visit required.Third parties: Card processing handled by an external payment processor (QuickPayProcessing Ltd) with API-based daily settlement file exchange.Data handled: Cardholder PII (name, address, SSN last-4), transaction history, devicefingerprint.	1	\N	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-09-30 11:23:10.755828+00
dd75b413-3645-47b7-a441-2693ab1e4aa4	846abe95-3e9a-438f-9b30-0c7097371a27	Team Registration for Panel Review.xlsx	application/vnd.openxmlformats-officedocument.spreadsheetml.sheet	https://stghdev01.blob.core.windows.net/change-request-attachments/33f47117-2809-44da-8173-021a4f986a11-Team Registration for Panel Review.xlsx	Team Members  (one row per person — include the Captain) Select Team Name from the dropdown · Rows 5–8 are examples · Allocation = % of the member's time spent on this project S.No Team Name Member Name Member Email ID Is Captain? Primary Role Secondary Role (if combination) Other Role Details Allocation (%) Remarks Example Code Crusaders Priya Sharma priya.sharma@company.com Yes Solution Architect Business Analyst (BA) 1 Captain Example Code Crusaders Rahul Mehta rahul.mehta@company.com No Developer - Backend 1 Example Code Crusaders Anjali Rao anjali.rao@company.com No Tester / QA Business Analyst (BA) 0.75 Example Code Crusaders Karan Patil karan.patil@company.com No UI/UX Designer Other Demo video editing 0.5 1 Humaid Risk Governance Suraj Koditala suraj.koditala@myridius.com Yes DevOps / Cloud Engineer Scrum Master / Project Manager Presenter 1 2 Humaid Risk Governance Shanthi Subramanian Shanthi.Subramanian@myridius.com No Tester / QA Business Analyst (BA) Presenter 1 3 Humaid Risk Governance Mohd Suleman Mohd.Suleman@myridius.com  No Developer - Full Stack Other DB Engineer 1 4 Humaid Risk Governance Francis T Daray Francis.Daray@myridius.com  No Developer - Full Stack Other AI Engineer 1 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70 71 72 73 74 75 76 77 78 79 80 81 82 83 84 85 86 87 88 89 90 91 92 93 94 95 96 97 98 99 100 101 102 103 104 105 106 107 108 109 110 111 112 113 114 115 116 117 118 119 120 121 122 123 124 125 126 127 128 129 130 131 132 133 134 135 136 137 138 139 140 141 142 143 144 145 146 147 148 149 150 151 152 153 154 155 156 157 158 159 160 161 162 163 164 165 166 167 168 169 170 171 172 173 174 175 176 177 178 179 180 181 182 183 184 185 186 187 188 189 190 191 192 193 194 195 196 197 198 199 200 201 202 203 204 205 206 207 208 209 210 211 212 213 214 215 216 217 218 219 220 221 222 223 224 225 226 227 228 229 230 231 232 233 234 235 236 237 238 239 240 241 242 243 244 245 246 247 248 249 250 251 252 253 254 255 256 257 258 259 260 261 262 263 264 265 266 267 268 269 270 271 272 273 274 275 276 277 278 279 280 281 282 283 284 285 286 287 288 289 290 291 292 293 294 295 296 297 298 299 300 301 302 303 304 305 306 307 308 309 310 311 312 313 314 315 316 317 318 319 320 321 322 323 324 325 326 327 328 329 330 331 332 333 334 335 336 337 338 339 340 341 342 343 344 345 346 347 348 349 350 351 352 353 354 355 356 357 358 359 360 361 362 363 364 365 366 367 368 369 370 371 372 373 374 375 376 377 378 379 380 381 382 383 384 385 386 387 388 389 390 391 392 393 394 395 396 397 \nTeam Details  (one row per team) Yellow = fill in  ·  Green = auto-calculated  ·  Row 5 is an example S.No Team Name Captain Name Captain Email ID GitHub Repository Link No. of Members Captain Listed in Members? Status Example Code Crusaders Priya Sharma priya.sharma@company.com https://github.com/codecrusaders/smart-inventory 4 Yes ✓ Complete 1 Humaid Risk Governance Suraj Koditala suraj.koditala@myridius.com https://github.com/surajkoditala/humaid-risk-governance 4 Yes ✓ Complete 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 \nGenius Hacks — Team Registration for Panel Presentation To be filled in by the Team Captain Step 1 — Team Details Go to the 'Team Details' tab. Enter your Team Name, your name as Captain, your email ID and your project's GitHub repository link. One row per team. Step 2 — Team Members Go to the 'Team Members' tab. Add ONE ROW PER PERSON, including yourself (the Captain). Select your Team Name from the dropdown so each member is linked to your team. Step 3 — Roles Pick a Primary Role from the dropdown. If the person played a combination role (e.g. BA + Tester), pick the second role in 'Secondary Role'. Use 'Other Role Details' for anything not in the list. Step 4 — Allocation Enter the percentage of that member's time/effort spent on this project Step 5 — Check status Return to 'Team Details'. The green columns fill in automatically: member count, captain listed, and a Status check. Aim for '✓ Complete'. Step 6 — Submit Save the file as <TeamName>_Registration.xlsx and send it to Vartika Jindal Legend Yellow cells — fill these in Green cells — calculated automatically, do not edit Grey italic row — example only, overwrite or leave as is (it is not counted) Rules • Every team member must have their own row — including the Captain (mark 'Is Captain?' = Yes). • Each team must have exactly one Captain. • Email IDs must be valid (contain @). GitHub link must start with https://github.com/ • Team Name on 'Team Members' must match exactly — always use the dropdown. \nRoles Yes/No Edit the role list here if your hackathon uses different roles. Dropdowns update automatically. Solution Architect Yes Business Analyst (BA) No Developer - Frontend Developer - Backend Developer - Full Stack Tester / QA UI/UX Designer Data Scientist / ML Engineer DevOps / Cloud Engineer Product Owner Scrum Master / Project Manager Presenter / Pitch Lead Other	1	\N	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-10-01 17:34:49.752133+00
1a7cd49f-7d55-4106-94a9-d00af9130b4b	d92baa78-c3dc-4ea5-ac3f-89b79959397d	vendor-due-diligence.pdf	application/pdf	https://stghdev01.blob.core.windows.net/change-request-attachments/57580ca9-67fb-478a-a9aa-77d5de24c517-vendor-due-diligence.pdf	QA-E2E Vendor Due Diligence Summary. Vendor name: QuickPay Processing Ltd. Jurisdiction: Malta. Data access scope: cardholder PII and settlement files. Customer types affected: retail cardholders, MSB merchants. Delivery channel: API, non-face-to-face.	1	\N	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-10-05 09:13:58.979738+00
6d166471-482b-4657-8640-bd29a57e4a43	d92baa78-c3dc-4ea5-ac3f-89b79959397d	product-spec.docx	application/vnd.openxmlformats-officedocument.wordprocessingml.document	https://stghdev01.blob.core.windows.net/change-request-attachments/13aa1a12-6fff-4f23-9eb6-8a82746fa9d4-product-spec.docx	QA-E2E Vendor Due Diligence Summary. Vendor name: QuickPay Processing Ltd. Jurisdiction: Malta. Data access scope: cardholder PII and settlement files. Customer types affected: retail cardholders, MSB merchants. Delivery channel: API, non-face-to-face.	1	\N	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-10-05 09:14:10.255263+00
618d9907-2cde-4efc-9731-27e2ada90ff4	d92baa78-c3dc-4ea5-ac3f-89b79959397d	control-matrix.xlsx	application/vnd.openxmlformats-officedocument.spreadsheetml.sheet	https://stghdev01.blob.core.windows.net/change-request-attachments/736ffbe4-5e5b-47ec-abbb-be6cc368a70b-control-matrix.xlsx	0.8	1	\N	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	2026-10-05 09:14:21.258062+00
\.


--
-- Data for Name: change_request_clarification; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.change_request_clarification (id, change_request_id, requested_by_user_id, question, status, answer, answered_at, created_at) FROM stdin;
8e661d25-f232-4a66-9031-23670b89c9aa	5c23a789-398d-4685-bbf6-f4977f7c9d6f	4fa322d3-2245-44ef-b664-1a804442db23	Which target countries exactly?	Open	\N	\N	2026-09-25 06:49:40.87516+00
a9f95b5a-9001-4baa-b82e-6d0b9be40ad3	c73e1706-d774-4fb7-9a86-95f260c31f2b	4fa322d3-2245-44ef-b664-1a804442db23	Which target countries exactly?	Open	\N	\N	2026-09-25 06:50:18.019016+00
7be6b406-d0e6-4907-aa52-7afc7ea12b65	ba127540-de51-4e40-989e-29b7bb56ec57	4fa322d3-2245-44ef-b664-1a804442db23	Which target countries exactly?	Open	\N	\N	2026-09-25 07:22:17.719042+00
04632043-f561-43f6-98b4-6ea2b4b73fea	62d2e0eb-c313-408c-b0b1-70ffe1196565	4fa322d3-2245-44ef-b664-1a804442db23	Which target countries exactly?	Open	\N	\N	2026-09-28 08:00:30.294633+00
fceaa5f1-5137-41f3-a947-015ab0677b33	1676366d-3ee4-4d55-993d-afcd3dc38b9a	4fa322d3-2245-44ef-b664-1a804442db23	QA-FT 05Oct: Which customer segments are in scope for the online KYC refresh, and what identity verification method will be used?	Open	\N	\N	2026-10-05 09:31:42.445852+00
\.


--
-- Data for Name: change_request_external_snapshot; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.change_request_external_snapshot (id, change_request_id, mock_customer_id, customer_risk_context, mock_product_id, product_risk_context, mock_vendor_id, vendor_risk_context, ingested_at) FROM stdin;
892579d7-fee9-4fb9-a591-fde13ff5ca81	87057aee-66d0-4eed-b503-ee593be28113	\N	\N	\N	\N	c3333333-0000-0000-0000-000000000002	{"Id": "c3333333-0000-0000-0000-000000000002", "VendorName": "QuickPay Processing LLC", "DataAccessScope": "Full transaction data, card PANs", "VendorRiskRating": "High", "VendorJurisdiction": "Cayman Islands", "CertificationStatus": "None"}	2026-09-22 15:32:15.281747+00
2c27c33a-779e-4c18-8616-ec5447f1e659	fd8253fb-6283-4e71-9b9c-53bf0ca1790f	\N	\N	b2222222-0000-0000-0000-000000000003	{"Id": "b2222222-0000-0000-0000-000000000003", "ProductName": "Prepaid Travel Card", "ProductType": "PrepaidAccess", "LaunchChangeType": "New", "ProductGeography": "United Arab Emirates"}	\N	\N	2026-09-25 06:49:22.156129+00
02ea6323-9305-4fd9-8748-f93b540ab470	e83eae48-d616-48ec-8947-e81e3bc4e0f3	\N	\N	b2222222-0000-0000-0000-000000000001	{"Id": "b2222222-0000-0000-0000-000000000001", "ProductName": "Cross-Border Wire Transfer Plus", "ProductType": "WireTransfer", "LaunchChangeType": "New", "ProductGeography": "Bangladesh"}	\N	\N	2026-09-25 06:49:42.110195+00
e372c550-b0aa-4667-8daf-b0360dce5902	97305b4b-fdb8-418c-9987-3cfafcd1d1dd	\N	\N	b2222222-0000-0000-0000-000000000003	{"Id": "b2222222-0000-0000-0000-000000000003", "ProductName": "Prepaid Travel Card", "ProductType": "PrepaidAccess", "LaunchChangeType": "New", "ProductGeography": "United Arab Emirates"}	\N	\N	2026-09-25 06:50:00.389203+00
c09df84a-8833-4de7-932b-433f561ef566	a0c484e3-fdc0-4275-bbee-51fec3c0f04d	\N	\N	b2222222-0000-0000-0000-000000000001	{"Id": "b2222222-0000-0000-0000-000000000001", "ProductName": "Cross-Border Wire Transfer Plus", "ProductType": "WireTransfer", "LaunchChangeType": "New", "ProductGeography": "Bangladesh"}	\N	\N	2026-09-25 06:50:19.302948+00
ecdaed44-a868-472f-b8db-8d6e06405ce4	89313b30-9064-4caa-8838-29e42ddc72f2	\N	\N	\N	\N	c3333333-0000-0000-0000-000000000001	{"Id": "c3333333-0000-0000-0000-000000000001", "VendorName": "Global KYC Solutions Inc", "DataAccessScope": "Customer PII for identity verification", "VendorRiskRating": "Medium", "VendorJurisdiction": "Singapore", "CertificationStatus": "Certified"}	2026-09-25 06:53:46.925689+00
760e2b35-bd57-4baa-baca-d56f75556fe5	298d4e01-a257-407a-9f27-04b96c02ff54	\N	\N	\N	\N	c3333333-0000-0000-0000-000000000001	{"Id": "c3333333-0000-0000-0000-000000000001", "VendorName": "Global KYC Solutions Inc", "DataAccessScope": "Customer PII for identity verification", "VendorRiskRating": "Medium", "VendorJurisdiction": "Singapore", "CertificationStatus": "Certified"}	2026-09-25 06:58:38.637477+00
065684bd-c545-44e6-a181-e73f750245fe	9c73424d-30b2-4a3e-8881-c25af94572ba	\N	\N	\N	\N	c3333333-0000-0000-0000-000000000001	{"Id": "c3333333-0000-0000-0000-000000000001", "VendorName": "Global KYC Solutions Inc", "DataAccessScope": "Customer PII for identity verification", "VendorRiskRating": "Medium", "VendorJurisdiction": "Singapore", "CertificationStatus": "Certified"}	2026-09-25 07:08:16.107116+00
9b614dac-7afd-41e6-b82f-e9673ec75662	7e97dfcc-50bd-40a8-b0cb-5db666f40111	\N	\N	b2222222-0000-0000-0000-000000000003	{"Id": "b2222222-0000-0000-0000-000000000003", "ProductName": "Prepaid Travel Card", "ProductType": "PrepaidAccess", "LaunchChangeType": "New", "ProductGeography": "United Arab Emirates"}	\N	\N	2026-09-25 07:21:58.176392+00
18ee0c6a-2be1-4619-9ac8-29887f3501f1	91d32e88-acb4-4f61-9053-e7ce06c9f89f	\N	\N	b2222222-0000-0000-0000-000000000001	{"Id": "b2222222-0000-0000-0000-000000000001", "ProductName": "Cross-Border Wire Transfer Plus", "ProductType": "WireTransfer", "LaunchChangeType": "New", "ProductGeography": "Bangladesh"}	\N	\N	2026-09-25 07:22:18.99228+00
b83e0e9a-7bd4-4d30-89cb-670df056468a	ef797803-aaf9-4a7a-b7af-a86f6f010f9a	\N	\N	\N	\N	c3333333-0000-0000-0000-000000000001	{"Id": "c3333333-0000-0000-0000-000000000001", "VendorName": "Global KYC Solutions Inc", "DataAccessScope": "Customer PII for identity verification", "VendorRiskRating": "Medium", "VendorJurisdiction": "Singapore", "CertificationStatus": "Certified"}	2026-09-25 07:22:21.191721+00
bfbd503c-b37d-4844-8f5f-fe4fa7b8e0dd	507e6f32-ab80-40db-81bd-5f641ef033a4	\N	\N	\N	\N	c3333333-0000-0000-0000-000000000001	{"Id": "c3333333-0000-0000-0000-000000000001", "VendorName": "Global KYC Solutions Inc", "DataAccessScope": "Customer PII for identity verification", "VendorRiskRating": "Medium", "VendorJurisdiction": "Singapore", "CertificationStatus": "Certified"}	2026-09-25 07:25:29.088453+00
3356ccf8-63a3-45f0-9d42-362e2f4d2fb4	2f3859fc-cf3f-44fe-88d3-9ab40b8585e4	\N	\N	b2222222-0000-0000-0000-000000000003	{"Id": "b2222222-0000-0000-0000-000000000003", "ProductName": "Prepaid Travel Card", "ProductType": "PrepaidAccess", "LaunchChangeType": "New", "ProductGeography": "United Arab Emirates"}	\N	\N	2026-09-28 08:00:05.894158+00
82922b93-a778-4045-a61f-5ad85f795dcf	8dce6573-54e9-41c3-a3f0-9b615351582d	\N	\N	b2222222-0000-0000-0000-000000000001	{"Id": "b2222222-0000-0000-0000-000000000001", "ProductName": "Cross-Border Wire Transfer Plus", "ProductType": "WireTransfer", "LaunchChangeType": "New", "ProductGeography": "Bangladesh"}	\N	\N	2026-09-28 08:00:31.606928+00
14df3aa3-3829-418e-9f94-36ddd3c394c6	617f16d3-e50b-487c-a31d-cedbbc7b572a	\N	\N	\N	\N	c3333333-0000-0000-0000-000000000001	{"Id": "c3333333-0000-0000-0000-000000000001", "VendorName": "Global KYC Solutions Inc", "DataAccessScope": "Customer PII for identity verification", "VendorRiskRating": "Medium", "VendorJurisdiction": "Singapore", "CertificationStatus": "Certified"}	2026-09-28 08:00:33.834771+00
4e174587-d095-485b-b4cc-797143afdaa9	a6bbfac6-7b11-45b5-8c48-74c1efc1a343	\N	\N	\N	\N	c3333333-0000-0000-0000-000000000001	{"Id": "c3333333-0000-0000-0000-000000000001", "VendorName": "Global KYC Solutions Inc", "DataAccessScope": "Customer PII for identity verification", "VendorRiskRating": "Medium", "VendorJurisdiction": "Singapore", "CertificationStatus": "Certified"}	2026-09-28 08:04:26.992822+00
14daebc4-20ca-4b4b-8b7e-94f506490af0	455cb36d-c05b-46f3-bba4-2769c127a7d3	\N	\N	b2222222-0000-0000-0000-000000000004	{"Id": "b2222222-0000-0000-0000-000000000004", "ProductName": "Correspondent Settlement Account", "ProductType": "CorrespondentBanking", "LaunchChangeType": "New", "ProductGeography": "Kenya"}	\N	\N	2026-09-28 08:26:02.007712+00
185005f1-8bb0-4585-a94f-4e49f2622666	7a379245-0ee3-414a-884d-de47fc4ae358	\N	\N	\N	\N	c3333333-0000-0000-0000-000000000001	{"Id": "c3333333-0000-0000-0000-000000000001", "VendorName": "Global KYC Solutions Inc", "DataAccessScope": "Customer PII for identity verification", "VendorRiskRating": "Medium", "VendorJurisdiction": "Singapore", "CertificationStatus": "Certified"}	2026-09-28 08:39:13.20456+00
2d653e65-1dcb-4769-b4e7-307f661f164e	7a6b4b58-4a23-4844-8c3b-fd20377a720f	\N	\N	b2222222-0000-0000-0000-000000000001	{"Id": "b2222222-0000-0000-0000-000000000001", "ProductName": "Cross-Border Wire Transfer Plus", "ProductType": "WireTransfer", "LaunchChangeType": "New", "ProductGeography": "Bangladesh"}	\N	\N	2026-09-30 11:03:39.630385+00
19979068-037f-40d5-a629-790b41dc7c09	846abe95-3e9a-438f-9b30-0c7097371a27	\N	\N	b2222222-0000-0000-0000-000000000003	{"Id": "b2222222-0000-0000-0000-000000000003", "ProductName": "Prepaid Travel Card", "ProductType": "PrepaidAccess", "LaunchChangeType": "New", "ProductGeography": "United Arab Emirates"}	\N	\N	2026-09-30 11:15:56.789006+00
39c6e574-8e5a-438d-a57a-1eff882bb842	d92baa78-c3dc-4ea5-ac3f-89b79959397d	\N	\N	\N	\N	c3333333-0000-0000-0000-000000000002	{"Id": "c3333333-0000-0000-0000-000000000002", "VendorName": "QuickPay Processing LLC", "DataAccessScope": "Full transaction data, card PANs", "VendorRiskRating": "High", "VendorJurisdiction": "Cayman Islands", "CertificationStatus": "None"}	2026-10-05 09:11:38.238757+00
\.


--
-- Data for Name: change_request_sla; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.change_request_sla (change_request_id, sla_config_id, decided_at, e2e_actual_business_days, e2e_met) FROM stdin;
8400daf2-14ec-489a-878f-2053e67a1d31	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
c73e1706-d774-4fb7-9a86-95f260c31f2b	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
a0c484e3-fdc0-4275-bbee-51fec3c0f04d	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
40affe4d-9ba8-48a6-b354-d60668956ac6	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
9fd8d7bc-d6d7-4e7a-912f-f375ddd98a6c	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
fd8253fb-6283-4e71-9b9c-53bf0ca1790f	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
7613c46e-1aa4-4260-8027-22e0114d760d	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
52b609f3-3f61-4b2e-9bfa-0e215555b5d5	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
09a5036e-ad3f-48ff-b2cf-fce2b8ada8e4	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
1d6e0018-0dbe-4b67-b4ae-eb80a828c493	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
8d3e5920-b652-492a-8bfc-a267db3389d6	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
5bcb3b1d-d7cc-41a7-8d39-277aa7a76694	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
5de8ab3f-5c62-4f6a-a40b-360a6cabd8d1	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
6dbe79eb-3aec-4d08-bcbf-f06873955cd1	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
caef4c84-30cc-40b5-9675-492cab0ee7a6	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
5c23a789-398d-4685-bbf6-f4977f7c9d6f	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
e83eae48-d616-48ec-8947-e81e3bc4e0f3	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
eee8de4f-c64c-436e-92b3-f9c85e7b3d91	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
97305b4b-fdb8-418c-9987-3cfafcd1d1dd	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
99fe5bab-2439-4d0e-8be6-20e5656ad100	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
24611c0a-41dc-4d53-a30d-d6b4b4cc1678	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
b6547a00-7b54-49b6-b57f-7bef8b75019e	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
cff8bed1-7fce-4d6e-a0bf-b23161306c4e	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
1083ff18-0335-423f-9ae8-a735fe833302	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
506888b7-0548-4f31-91fc-8ee9d999bad0	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
3976f8cd-9fce-4858-b550-2ba02670603c	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
b5e1065a-a458-4f71-a672-0d3a516a4578	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
d80b9214-6103-4950-bbbf-e2ed93d18531	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
9782168a-6d7f-479a-ae0a-ca201f728af2	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
aff5b2e9-5ae7-4adf-8bf8-23de8bdca397	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
fdde906d-fee7-4abe-ab0a-3372b4e0f9b5	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
9c73424d-30b2-4a3e-8881-c25af94572ba	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
a4614f58-6f4f-45bf-92fb-1d652866657e	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
7e97dfcc-50bd-40a8-b0cb-5db666f40111	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
83fd772d-e35b-4f9c-9d75-c4064841e157	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
c2f156eb-e295-44e9-ad78-723a35feefb8	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
f0ce4db6-ca13-4f7c-a468-d6651c2e34be	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
efbde630-cc1f-4931-8635-0941776edec5	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
1574b600-6773-46a4-a30e-1f7664101fc1	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
be27434a-b46d-4f8c-8f97-790e413248f7	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
fc726513-8a52-42e1-a104-fcbf7d023ab2	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
9c895ced-c6aa-44af-a2f3-d7d96fb72c43	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
7a6ea15a-41be-4f29-9882-0921a6ffbe48	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
ba127540-de51-4e40-989e-29b7bb56ec57	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
91d32e88-acb4-4f61-9053-e7ce06c9f89f	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
6a78af14-7388-4b01-8352-68ebf57be9a6	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
89c78436-ebd6-41fc-bdc0-0c7c9807d8b8	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
0a731172-0bbb-4489-aec4-db7828dd5928	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
cc995f7a-83e3-493f-b12c-ab0f43097f3a	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
bea75b32-b4c1-45d7-8ec9-65598745cf4e	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
e61cc526-3149-4f64-ac51-03cf2d2612f6	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
b1c408c0-01d2-4d51-b5e9-20cb5fdfba0a	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
de00fb95-f4e9-4c55-9d17-781709873552	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
eee96cea-4f87-4d0d-95bd-565397ba8cea	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
0833e6e4-c347-4e8a-8be2-b3d3f722d1ab	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
a9d2beb0-3e2b-4931-bced-0f79150dac20	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
11f899a8-e66a-4572-915e-b077ecf43280	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
95c5cf1d-f648-489c-8391-20721104947f	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
2f3859fc-cf3f-44fe-88d3-9ab40b8585e4	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
55d227e6-ab38-4a7b-b2b2-271a6482b96b	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
4fd54ca9-b073-4733-94a5-4ab3e7b61c01	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
62d2e0eb-c313-408c-b0b1-70ffe1196565	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
8dce6573-54e9-41c3-a3f0-9b615351582d	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
7f4b8f70-f2cc-4aca-890a-876a16f9860a	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
a3e3e745-edef-45d1-a62f-c20dbb048de0	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
b3976f2e-4b74-4091-9aea-66af92b07bc5	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
2afd7b9b-a899-466e-82e2-e58da781599a	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
e7983599-9aee-492c-8444-8764ae4892d9	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
663e4342-4b4a-43ef-b6c2-a088ef3ce1cc	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
455cb36d-c05b-46f3-bba4-2769c127a7d3	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
f278bcec-0b6e-4cad-a299-3cf307eb2a01	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
823b48e6-5235-4fdf-9aa9-17ceb9417cd5	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
724a96ec-6d75-4ebd-9ed5-d15d7abcccca	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
1db33cf3-d01d-4b60-8466-20fce8524875	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
846abe95-3e9a-438f-9b30-0c7097371a27	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
7a6b4b58-4a23-4844-8c3b-fd20377a720f	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
d92baa78-c3dc-4ea5-ac3f-89b79959397d	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
bf57f2fb-8d22-4567-a0d3-6eed60680461	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
a7ae047c-a52c-40dd-a9d6-7840e8e7a87a	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
1676366d-3ee4-4d55-993d-afcd3dc38b9a	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
d926e791-83f0-4a97-bf81-27057c1c914b	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
3f0eaf26-cf7d-4bb3-921c-162f6ae43a3d	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
14f9fd2e-6c57-4b13-80ad-2358f79aef97	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
4fe145bd-924b-4d09-83c4-3d9b3981a88d	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	\N	\N	\N
87057aee-66d0-4eed-b503-ee593be28113	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	2026-09-22 15:43:21.169626+00	0	t
bd7b9737-77c8-4564-8a78-2d64ba3060a3	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	2026-09-24 17:33:13.407376+00	0	t
89313b30-9064-4caa-8838-29e42ddc72f2	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	2026-09-25 06:54:48.882644+00	0	t
83f2c245-439e-4b8a-8206-ee1bda436d80	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	2026-09-25 06:59:43.441949+00	0	t
298d4e01-a257-407a-9f27-04b96c02ff54	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	2026-09-25 06:59:50.836323+00	0	t
18404cb0-2e0b-4ef4-9a7d-b06fffe699f5	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	2026-09-25 07:23:30.023872+00	0	t
ef797803-aaf9-4a7a-b7af-a86f6f010f9a	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	2026-09-25 07:23:38.508341+00	0	t
507e6f32-ab80-40db-81bd-5f641ef033a4	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	2026-09-25 07:29:26.454241+00	0	t
540ffca2-0e67-4ed9-9e72-39e1aa12152d	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	2026-09-28 08:01:54.955342+00	0	t
617f16d3-e50b-487c-a31d-cedbbc7b572a	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	2026-09-28 08:02:04.661138+00	0	t
a6bbfac6-7b11-45b5-8c48-74c1efc1a343	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	2026-09-28 08:08:09.781125+00	0	t
7a379245-0ee3-414a-884d-de47fc4ae358	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	2026-09-29 17:43:44.698289+00	1	t
ac11f587-ee4f-40e6-a72f-e7e8f6be308a	b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	2026-10-05 09:30:52.886257+00	4	t
90acf576-4272-4b63-bf8c-b55461910c28	8a75bac7-b9ba-4928-a791-97e0ccefa082	\N	\N	\N
\.


--
-- Data for Name: change_request_stage_history; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.change_request_stage_history (id, change_request_id, stage, entered_at, left_at, target_business_days, actual_business_days, met_sla) FROM stdin;
8c87d532-3b47-4cb5-85a1-b6db9da61c62	8400daf2-14ec-489a-878f-2053e67a1d31	InAssessment	2026-09-22 15:28:31.951764+00	\N	8	\N	\N
3693be08-ef32-4751-8519-57052f1d54b0	c73e1706-d774-4fb7-9a86-95f260c31f2b	Submitted	2026-09-25 06:50:17.709215+00	\N	2	\N	\N
fcd15f0f-9083-4571-bbf0-53a31b1791dc	a0c484e3-fdc0-4275-bbee-51fec3c0f04d	Submitted	2026-09-25 06:50:19.236347+00	\N	2	\N	\N
fff4e1b0-c55e-4a8c-8d65-df71a3c3431b	40affe4d-9ba8-48a6-b354-d60668956ac6	Submitted	2026-09-25 06:50:19.597754+00	\N	2	\N	\N
0e0d8534-68a7-428e-995f-58de218230f1	9fd8d7bc-d6d7-4e7a-912f-f375ddd98a6c	Submitted	2026-09-25 06:50:40.560319+00	\N	2	\N	\N
f1357c05-1129-49fd-9679-66219f6f5329	fd8253fb-6283-4e71-9b9c-53bf0ca1790f	Submitted	2026-09-25 06:49:22.047018+00	\N	2	\N	\N
fbe59f41-bbb0-47f4-bac8-a7b5b19ffd4a	7613c46e-1aa4-4260-8027-22e0114d760d	Submitted	2026-09-25 06:49:22.990982+00	\N	2	\N	\N
696cec76-297f-411e-aac2-fb8033c21274	52b609f3-3f61-4b2e-9bfa-0e215555b5d5	Submitted	2026-09-25 06:49:23.278225+00	\N	2	\N	\N
f1c72930-b51f-4aaa-85c5-16f9a33b27f6	09a5036e-ad3f-48ff-b2cf-fce2b8ada8e4	Submitted	2026-09-25 06:49:23.566589+00	\N	2	\N	\N
fead6a7f-a125-45b3-9843-41fdf740f33a	1d6e0018-0dbe-4b67-b4ae-eb80a828c493	Submitted	2026-09-25 06:49:23.85048+00	\N	2	\N	\N
6d581140-889b-4e51-b2a4-a179a4bce0e3	8d3e5920-b652-492a-8bfc-a267db3389d6	Submitted	2026-09-25 06:49:24.134701+00	\N	2	\N	\N
a6fab159-9a37-400a-b8c0-c28a2126ecb7	5bcb3b1d-d7cc-41a7-8d39-277aa7a76694	Submitted	2026-09-25 06:49:24.411171+00	\N	2	\N	\N
6afbf3b2-08ca-4ede-b5c7-b2ff7d9b53ef	5de8ab3f-5c62-4f6a-a40b-360a6cabd8d1	Submitted	2026-09-25 06:49:26.117233+00	\N	2	\N	\N
4d408bdd-28c1-47c2-92ce-67c3a6187c50	6dbe79eb-3aec-4d08-bcbf-f06873955cd1	Submitted	2026-09-25 06:49:33.021022+00	\N	2	\N	\N
f9edfeaf-0238-4537-b4f1-04594fffe46a	caef4c84-30cc-40b5-9675-492cab0ee7a6	Submitted	2026-09-25 06:49:37.716834+00	\N	2	\N	\N
8f0807c6-e1c4-4aef-9c93-e25993b9e9cf	5c23a789-398d-4685-bbf6-f4977f7c9d6f	Submitted	2026-09-25 06:49:40.541984+00	\N	2	\N	\N
0c5250dc-7376-4261-bfd9-ed0fb6016566	e83eae48-d616-48ec-8947-e81e3bc4e0f3	Submitted	2026-09-25 06:49:42.043857+00	\N	2	\N	\N
af30f971-6253-4b49-b9e0-1dea1ace1849	eee8de4f-c64c-436e-92b3-f9c85e7b3d91	Submitted	2026-09-25 06:49:42.405273+00	\N	2	\N	\N
cd21073b-5a6e-401e-99d0-b580d1af2356	97305b4b-fdb8-418c-9987-3cfafcd1d1dd	Submitted	2026-09-25 06:50:00.31761+00	\N	2	\N	\N
7aa336b5-943d-4937-9066-9f72ba492819	99fe5bab-2439-4d0e-8be6-20e5656ad100	Submitted	2026-09-25 06:50:01.319542+00	\N	2	\N	\N
7aca7084-b124-4212-a347-dc95cd901d27	24611c0a-41dc-4d53-a30d-d6b4b4cc1678	Submitted	2026-09-25 06:50:01.925024+00	\N	2	\N	\N
47c7256a-bf73-4696-b973-62fc80ddc4c5	b6547a00-7b54-49b6-b57f-7bef8b75019e	Submitted	2026-09-25 06:50:02.225653+00	\N	2	\N	\N
dfb242f5-ee9e-48a6-ad56-d40b42948ef9	cff8bed1-7fce-4d6e-a0bf-b23161306c4e	Submitted	2026-09-25 06:50:02.519935+00	\N	2	\N	\N
cc9adf1b-8068-4403-b685-64e7e3fd1239	1083ff18-0335-423f-9ae8-a735fe833302	Submitted	2026-09-25 06:50:02.805663+00	\N	2	\N	\N
205d7af6-70e6-4da2-a6c2-a4f158398115	506888b7-0548-4f31-91fc-8ee9d999bad0	Submitted	2026-09-25 06:50:04.552981+00	\N	2	\N	\N
434ecbce-9fca-45e5-a504-2332affb02b2	3976f8cd-9fce-4858-b550-2ba02670603c	Submitted	2026-09-25 06:50:11.579863+00	\N	2	\N	\N
b2def9e6-85db-4523-b4b1-a26ee5dfd09a	b5e1065a-a458-4f71-a672-0d3a516a4578	Submitted	2026-09-25 06:50:14.895356+00	\N	2	\N	\N
dddaf1ce-0684-418d-aa92-285f48956d46	d80b9214-6103-4950-bbbf-e2ed93d18531	PendingCommittee	2026-09-25 06:59:46.528673+00	\N	5	\N	\N
5cc34d30-0621-404b-9570-24e39915cc84	9782168a-6d7f-479a-ae0a-ca201f728af2	InAssessment	2026-09-25 07:02:32.026949+00	\N	8	\N	\N
7d7b4f59-958e-4b35-8341-61f0e6a2fb28	aff5b2e9-5ae7-4adf-8bf8-23de8bdca397	InAssessment	2026-09-25 07:02:21.127777+00	\N	8	\N	\N
a9e1b809-aad6-4d26-8013-644d5110a2e6	fdde906d-fee7-4abe-ab0a-3372b4e0f9b5	Submitted	2026-09-25 07:02:47.355479+00	\N	2	\N	\N
cbfbc302-73c5-4ce8-b1e0-2a17cdb9f100	9c73424d-30b2-4a3e-8881-c25af94572ba	InAssessment	2026-09-25 07:11:34.399672+00	\N	8	\N	\N
51e11546-b161-4103-9005-bb31e4b0aded	a4614f58-6f4f-45bf-92fb-1d652866657e	Submitted	2026-09-25 07:20:20.08475+00	\N	2	\N	\N
09163c1d-eb02-43fa-8801-bdfb56fd27c6	7e97dfcc-50bd-40a8-b0cb-5db666f40111	Submitted	2026-09-25 07:21:58.094958+00	\N	2	\N	\N
48f35003-745e-4608-aee9-a856f252e444	83fd772d-e35b-4f9c-9d75-c4064841e157	Submitted	2026-09-25 07:21:59.081579+00	\N	2	\N	\N
e10c4b66-a0d3-4a94-acc4-dca5f947ed47	c2f156eb-e295-44e9-ad78-723a35feefb8	Submitted	2026-09-25 07:21:59.387397+00	\N	2	\N	\N
f523b68c-063f-4773-a400-b1eaa47b97ad	f0ce4db6-ca13-4f7c-a468-d6651c2e34be	Submitted	2026-09-25 07:21:59.698513+00	\N	2	\N	\N
7c3ddcc4-637f-4fd1-8866-22b5a8594631	efbde630-cc1f-4931-8635-0941776edec5	Submitted	2026-09-25 07:21:59.987346+00	\N	2	\N	\N
00337b40-b689-441b-8b35-ed3b02f84473	1574b600-6773-46a4-a30e-1f7664101fc1	Submitted	2026-09-25 07:22:00.28372+00	\N	2	\N	\N
378a5a94-21cd-4d69-ad3e-13f086ed0af9	be27434a-b46d-4f8c-8f97-790e413248f7	Submitted	2026-09-25 07:22:00.584982+00	\N	2	\N	\N
336a8290-ba29-4793-9fcd-1bdcb5de450c	fc726513-8a52-42e1-a104-fcbf7d023ab2	Submitted	2026-09-25 07:22:02.524814+00	\N	2	\N	\N
38685282-fc5e-4321-b8e9-aaed1fffe801	9c895ced-c6aa-44af-a2f3-d7d96fb72c43	Submitted	2026-09-25 07:22:10.907194+00	\N	2	\N	\N
aaf47905-df91-4803-988a-1e2fe1dafed8	7a6ea15a-41be-4f29-9882-0921a6ffbe48	Submitted	2026-09-25 07:22:14.640162+00	\N	2	\N	\N
a62b5a07-44b2-422c-9ed1-e77d607ed3f7	ba127540-de51-4e40-989e-29b7bb56ec57	Submitted	2026-09-25 07:22:17.418978+00	\N	2	\N	\N
9d0473e8-0094-4bad-b930-7dcbd4cca824	91d32e88-acb4-4f61-9053-e7ce06c9f89f	Submitted	2026-09-25 07:22:18.92203+00	\N	2	\N	\N
e49cd421-7a63-48ad-9b49-d3b17ba1f94a	6a78af14-7388-4b01-8352-68ebf57be9a6	Submitted	2026-09-25 07:22:19.302835+00	\N	2	\N	\N
523211dd-4043-43c6-a7f3-cc6d8f560cf0	89c78436-ebd6-41fc-bdc0-0c7c9807d8b8	Submitted	2026-09-28 08:00:07.989647+00	\N	2	\N	\N
d2dfeaec-5da4-4f01-9274-8ccff0e8b259	0a731172-0bbb-4489-aec4-db7828dd5928	Submitted	2026-09-28 08:00:08.327834+00	\N	2	\N	\N
902d72ba-d223-4954-8fe7-1edcff2a860b	cc995f7a-83e3-493f-b12c-ab0f43097f3a	Submitted	2026-09-28 08:00:08.659638+00	\N	2	\N	\N
e199a547-839d-498d-8897-4c4db366dafc	bea75b32-b4c1-45d7-8ec9-65598745cf4e	Submitted	2026-09-28 08:00:08.986344+00	\N	2	\N	\N
24263df6-b26a-4673-bfd3-c20e1deb3960	e61cc526-3149-4f64-ac51-03cf2d2612f6	Submitted	2026-09-28 08:00:11.419736+00	\N	2	\N	\N
33f9ecbf-1a2f-4d30-bad4-c000bd3d5513	b1c408c0-01d2-4d51-b5e9-20cb5fdfba0a	PendingCommittee	2026-09-25 07:23:34.030714+00	\N	5	\N	\N
08de70b7-efb1-4227-b52b-1aa61c618732	de00fb95-f4e9-4c55-9d17-781709873552	InAssessment	2026-09-25 07:23:47.743389+00	\N	8	\N	\N
2e3be344-af34-4592-b361-c914ced90888	eee96cea-4f87-4d0d-95bd-565397ba8cea	InAssessment	2026-09-25 07:23:59.184479+00	\N	8	\N	\N
1f9104a7-5e44-44b0-845a-8e2e4347c322	0833e6e4-c347-4e8a-8be2-b3d3f722d1ab	Submitted	2026-09-25 07:24:15.21347+00	\N	2	\N	\N
87695498-15f9-4839-a4fb-2b05e5d2ae2d	a9d2beb0-3e2b-4931-bced-0f79150dac20	Submitted	2026-09-28 08:00:21.218879+00	\N	2	\N	\N
087c4856-9bd9-4e58-be35-feed7414d03c	11f899a8-e66a-4572-915e-b077ecf43280	Submitted	2026-09-28 08:00:26.619129+00	\N	2	\N	\N
1e86e32e-76ab-4eaf-a0e0-c5eb3147191d	95c5cf1d-f648-489c-8391-20721104947f	InAssessment	2026-09-25 07:30:47.668113+00	\N	8	\N	\N
f140f2ab-c388-404a-913f-96c4a151c0c8	2f3859fc-cf3f-44fe-88d3-9ab40b8585e4	Submitted	2026-09-28 08:00:05.779798+00	\N	2	\N	\N
b5ee32b1-e33f-491d-90f0-7db2e0efbbfe	55d227e6-ab38-4a7b-b2b2-271a6482b96b	Submitted	2026-09-28 08:00:07.287832+00	\N	2	\N	\N
944f277a-00f6-4568-bbef-6539f3dd1353	4fd54ca9-b073-4733-94a5-4ab3e7b61c01	Submitted	2026-09-28 08:00:07.65264+00	\N	2	\N	\N
a5415579-b3d5-4e74-a7f8-33c9be977536	62d2e0eb-c313-408c-b0b1-70ffe1196565	Submitted	2026-09-28 08:00:29.977655+00	\N	2	\N	\N
44bbc1d3-f8e0-4278-b8bd-f5f738ccf3c0	8dce6573-54e9-41c3-a3f0-9b615351582d	Submitted	2026-09-28 08:00:31.521582+00	\N	2	\N	\N
a6f9ada9-ed83-4411-9b25-8b22e05af3a2	7f4b8f70-f2cc-4aca-890a-876a16f9860a	Submitted	2026-09-28 08:00:31.903104+00	\N	2	\N	\N
625a147d-d783-4203-bcfc-fbd127bd89f4	a3e3e745-edef-45d1-a62f-c20dbb048de0	InAssessment	2026-09-28 08:02:14.660436+00	\N	8	\N	\N
046a118b-c29f-4166-af10-d6dbc50874e5	b3976f2e-4b74-4091-9aea-66af92b07bc5	Submitted	2026-09-28 08:08:38.758915+00	\N	2	\N	\N
3bacf7a5-b870-4be4-b592-e9ab4617488e	2afd7b9b-a899-466e-82e2-e58da781599a	PendingCommittee	2026-09-28 08:01:59.186728+00	\N	5	\N	\N
e35eaedc-728f-4f70-afb5-8606cc0ed4b7	e7983599-9aee-492c-8444-8764ae4892d9	InAssessment	2026-09-28 08:02:28.105223+00	\N	8	\N	\N
78f474e1-25f5-4af6-b0f1-144f9da86cdf	663e4342-4b4a-43ef-b6c2-a088ef3ce1cc	Submitted	2026-09-28 08:02:44.593376+00	\N	2	\N	\N
9eb1e16a-faf6-4d0b-bd08-3fc897b5b23a	455cb36d-c05b-46f3-bba4-2769c127a7d3	PendingCommittee	2026-09-28 08:32:05.578264+00	\N	5	\N	\N
8ec76563-8e50-4623-8da1-40ffa1ce4f2f	f278bcec-0b6e-4cad-a299-3cf307eb2a01	Submitted	2026-09-29 08:13:52.443819+00	\N	2	\N	\N
b7514646-500e-4909-8fab-87144ba79123	823b48e6-5235-4fdf-9aa9-17ceb9417cd5	InAssessment	2026-09-29 11:04:38.517019+00	\N	8	\N	\N
a8798596-ba59-445f-8bee-f3c96670ba19	724a96ec-6d75-4ebd-9ed5-d15d7abcccca	InAssessment	2026-09-30 10:40:38.288417+00	\N	8	\N	\N
74d3b83d-5596-497a-a345-288c74d5f2f7	1db33cf3-d01d-4b60-8466-20fce8524875	InAssessment	2026-10-05 09:58:31.596238+00	\N	8	\N	\N
ad76b967-61ae-4133-9cb5-47242ffdfacb	846abe95-3e9a-438f-9b30-0c7097371a27	PendingCommittee	2026-09-30 12:57:37.763475+00	\N	5	\N	\N
191ef1fa-033d-4017-aff0-d356910ade28	7a6b4b58-4a23-4844-8c3b-fd20377a720f	InAssessment	2026-09-30 14:47:50.459809+00	\N	8	\N	\N
0b0777dd-782a-4eed-b244-995aeb5f05c1	d92baa78-c3dc-4ea5-ac3f-89b79959397d	InAssessment	2026-10-05 09:15:06.661625+00	\N	8	\N	\N
c8c134b9-45ea-40ae-a7ca-3a75a74fbc5f	bf57f2fb-8d22-4567-a0d3-6eed60680461	InAssessment	2026-10-05 09:37:24.466161+00	\N	8	\N	\N
f65434e5-662f-4e08-bc9e-49573cbedba5	a7ae047c-a52c-40dd-a9d6-7840e8e7a87a	InAssessment	2026-10-05 09:37:25.945641+00	\N	8	\N	\N
6ae8103a-4833-41f7-b14e-3d6743cd33ef	1676366d-3ee4-4d55-993d-afcd3dc38b9a	InAssessment	2026-10-05 09:39:03.583992+00	\N	8	\N	\N
5824433a-d3bb-47d6-bed4-26569b443348	d926e791-83f0-4a97-bf81-27057c1c914b	Submitted	2026-10-05 09:40:38.901022+00	\N	2	\N	\N
ea355442-812c-46ac-b123-e8ba2b8436be	3f0eaf26-cf7d-4bb3-921c-162f6ae43a3d	InAssessment	2026-10-05 09:41:47.910354+00	\N	8	\N	\N
ff36db80-136c-4eac-9702-a20a843bd280	14f9fd2e-6c57-4b13-80ad-2358f79aef97	Submitted	2026-10-05 09:47:40.67464+00	\N	2	\N	\N
dfdff034-a7d1-4e09-b2de-1bd642fba305	4fe145bd-924b-4d09-83c4-3d9b3981a88d	InAssessment	2026-10-05 09:48:44.082347+00	\N	8	\N	\N
44befd38-0799-4438-a727-2cf431d32efc	90acf576-4272-4b63-bf8c-b55461910c28	Submitted	2026-10-07 14:07:05.667423+00	2026-10-07 14:36:59.327602+00	\N	0	\N
79a00623-5858-43cc-aebd-356dd1ff59b3	90acf576-4272-4b63-bf8c-b55461910c28	InAssessment	2026-10-07 14:36:59.327602+00	\N	\N	\N	\N
\.


--
-- Data for Name: change_request_type_category_map; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.change_request_type_category_map (id, change_type, risk_category_id, weight) FROM stdin;
4b187cc8-9073-4dcd-a234-df5da667a23c	Product	22222222-2222-2222-2222-222222222221	Primary
874c6358-3cb2-4029-aa15-d78baf8c03c7	Product	22222222-2222-2222-2222-222222222222	Secondary
7de8c94e-79d0-4ece-995d-2de6a4d95728	Feature	22222222-2222-2222-2222-222222222221	Primary
70606b6b-63f7-4136-b7ac-01aa407100ae	Process	22222222-2222-2222-2222-222222222224	Primary
c5e119c3-965e-462e-afb7-53b2b50493a0	Vendor	22222222-2222-2222-2222-222222222222	Primary
83b1eed4-03a2-434c-837c-baec0ec0f955	Geography	22222222-2222-2222-2222-222222222223	Primary
764eb298-59f7-48a1-b2c6-8b321439bb2c	Geography	22222222-2222-2222-2222-222222222221	Secondary
26ba6223-9b6e-43fc-b531-9c9a964e6d17	CustomerSegment	22222222-2222-2222-2222-222222222222	Primary
70c3e477-98b6-41ca-aeea-640644b89aad	Vendor	22222222-2222-2222-2222-222222222224	Primary
\.


--
-- Data for Name: committee_decision; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.committee_decision (id, assessment_id, resolution, conditions_text, decided_at) FROM stdin;
ed0c9443-9dbe-414b-80d5-bbbd2417021b	9cf350cf-b9d2-4b1e-8f49-4661be9594bb	ApprovedWithConditions	Jordan Blake: Vendor must obtain SOC 2 Type II certification within 90 days of go-live; quarterly compliance attestation required for the first year.	2026-09-22 15:43:21.169626+00
eb256c62-8d36-4b7c-a961-a56f89a98531	bcef5b36-6d28-4778-8653-4ea2b2798edf	Approved	\N	2026-09-24 17:33:13.407376+00
4f605330-0194-4b2f-9f16-8cafcc6975f6	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	Deferred	\N	2026-09-25 06:54:48.882644+00
53aabb7d-9b20-4ece-a088-926ad76fa749	12f0ad4a-87e9-494c-924e-20be52169763	Deferred	\N	2026-09-25 06:59:43.441949+00
61cea176-52dd-4866-848d-d57137b4e83f	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	ApprovedWithConditions	Jordan Blake: Annual on-site audit of the vendor; PII encrypted at rest	2026-09-25 06:59:50.836323+00
aafde869-a249-41d5-b790-c6fed1ff4f27	50f965f9-70e5-4c4d-bec5-36017302898e	Deferred	\N	2026-09-25 07:23:30.023872+00
93d8a260-c62c-4768-80e9-03056e8b0ed6	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	ApprovedWithConditions	Jordan Blake: Annual on-site audit of the vendor; PII encrypted at rest	2026-09-25 07:23:38.508341+00
9872b5b1-8173-4994-bd4e-015db347b5c2	a46d7e97-e303-4945-bf55-5ff7405b2a25	ApprovedWithConditions	Jordan Blake: Annual on-site audit of the vendor; cardholder PII encrypted at rest (QA)	2026-09-25 07:29:26.454241+00
a384e789-cf84-43da-9aaf-fde6164f0b3a	90b8631a-dba0-43a1-b722-92176fd4bd13	Deferred	\N	2026-09-28 08:01:54.955342+00
39adaf62-f4e8-4489-b9c6-342b0d1a70ec	9534f3f0-685a-4450-bfc0-983f2d16f7d9	ApprovedWithConditions	Jordan Blake: Annual on-site audit of the vendor; PII encrypted at rest	2026-09-28 08:02:04.661138+00
8bf3d37a-e50b-41f6-bbc2-c90046403831	fe6f95b7-3a35-4799-9eb2-e3239a6a3674	ApprovedWithConditions	Jordan Blake: Annual on-site audit of the vendor; cardholder PII encrypted at rest (QA)	2026-09-28 08:08:09.781125+00
7eae9615-971e-40ee-9113-1e2c03d3fb6d	eb5c9dbb-e31b-4d8b-8820-d13aa90fabc1	Approved	\N	2026-09-29 17:43:44.698289+00
8e4c5104-d0fa-49aa-9b6b-847896aa2335	b2a913c6-c962-4dfd-9961-810e58affc32	ApprovedWithConditions	Jordan Blake: QA-FT 05Oct conditions: quarterly review of prepaid reload limits; enhanced monitoring for cross-border loads	2026-10-05 09:30:52.886257+00
\.


--
-- Data for Name: committee_vote; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.committee_vote (id, assessment_id, committee_member_user_id, vote, conditions_text, rationale, voted_at) FROM stdin;
46525f86-18fe-4883-8d76-f54a6be546a2	9cf350cf-b9d2-4b1e-8f49-4661be9594bb	083ecfe5-aa01-4703-9168-762f0065078f	ApproveWithConditions	Vendor must obtain SOC 2 Type II certification within 90 days of go-live; quarterly compliance attestation required for the first year.	\N	2026-09-22 15:43:17.419501+00
8c429502-e0c7-4db6-9870-03db402ef3db	9cf350cf-b9d2-4b1e-8f49-4661be9594bb	fa142c1c-58cc-4666-b135-7768a2ab33f0	Approve	\N	\N	2026-09-22 15:43:19.714584+00
1bb1a668-9bee-4b39-8c01-f4b287e86b44	bcef5b36-6d28-4778-8653-4ea2b2798edf	083ecfe5-aa01-4703-9168-762f0065078f	Approve	\N	\N	2026-09-24 17:33:04.712445+00
38bc5b88-b1df-416a-978b-9de7a0b349d9	bcef5b36-6d28-4778-8653-4ea2b2798edf	fa142c1c-58cc-4666-b135-7768a2ab33f0	Approve	\N	\N	2026-09-24 17:33:12.182553+00
d4ee845c-3eaf-4d55-9a58-f55746395b01	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	083ecfe5-aa01-4703-9168-762f0065078f	Defer	\N	   	2026-09-25 06:54:47.898642+00
7563078a-c4fb-4822-8984-dad840ee1ae9	709e7f0b-5cc4-45ff-ac85-e19c2a56eab6	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	Approve	\N	\N	2026-09-25 06:54:48.757173+00
f5ff9f57-f1db-4a02-82b8-36f112e39673	12f0ad4a-87e9-494c-924e-20be52169763	083ecfe5-aa01-4703-9168-762f0065078f	Defer	\N	   	2026-09-25 06:59:42.534889+00
182e5ca3-267e-4dea-9635-8360a86f4521	12f0ad4a-87e9-494c-924e-20be52169763	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	Approve	\N	\N	2026-09-25 06:59:43.314206+00
a8b460d1-fc19-41d6-9276-9d05081163ab	35b32ea9-b582-47a4-ad59-ad953bc0f5af	083ecfe5-aa01-4703-9168-762f0065078f	Reject	\N	changed my mind	2026-09-25 06:59:47.599655+00
bce8b36c-5b4d-4d0d-8b81-d7a46683e18a	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	083ecfe5-aa01-4703-9168-762f0065078f	ApproveWithConditions	Annual on-site audit of the vendor; PII encrypted at rest	\N	2026-09-25 06:59:50.252839+00
ffb7083e-c452-4dfe-ab12-314e38bc113a	b3e33ccf-aa89-4fe0-92c3-4c4f0c78148a	fa142c1c-58cc-4666-b135-7768a2ab33f0	Approve	\N	\N	2026-09-25 06:59:50.711113+00
e0e39fce-7476-4503-a59c-97bc587cde38	50f965f9-70e5-4c4d-bec5-36017302898e	083ecfe5-aa01-4703-9168-762f0065078f	Defer	\N	   	2026-09-25 07:23:29.104309+00
49503cc7-0fe9-4d97-a8a9-cf7177d20505	50f965f9-70e5-4c4d-bec5-36017302898e	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	Approve	\N	\N	2026-09-25 07:23:29.899815+00
90d10b72-34ab-4700-8eee-2e4e68b76145	25ab4813-e18f-49c9-a50e-8541b5d63a10	083ecfe5-aa01-4703-9168-762f0065078f	Reject	\N	changed my mind	2026-09-25 07:23:35.129533+00
3a49fa0e-830d-4b3b-ae75-977b8d77c818	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	083ecfe5-aa01-4703-9168-762f0065078f	ApproveWithConditions	Annual on-site audit of the vendor; PII encrypted at rest	\N	2026-09-25 07:23:37.930855+00
2c433f59-84a4-46a5-ab83-b6aff078bcda	eba39f9c-a4ba-40cf-946d-fa0a3da1bb98	fa142c1c-58cc-4666-b135-7768a2ab33f0	Approve	\N	\N	2026-09-25 07:23:38.383984+00
47318d69-c173-4a44-bb87-8db325761c58	a46d7e97-e303-4945-bf55-5ff7405b2a25	083ecfe5-aa01-4703-9168-762f0065078f	ApproveWithConditions	Annual on-site audit of the vendor; cardholder PII encrypted at rest (QA)	\N	2026-09-25 07:29:18.301734+00
97c03a80-5032-4fe0-9aaf-a73c367df959	a46d7e97-e303-4945-bf55-5ff7405b2a25	fa142c1c-58cc-4666-b135-7768a2ab33f0	Approve	\N	\N	2026-09-25 07:29:26.315845+00
9ff4a58e-7d55-40ce-b4e3-1e4ed7b6f9e9	90b8631a-dba0-43a1-b722-92176fd4bd13	083ecfe5-aa01-4703-9168-762f0065078f	Defer	\N	   	2026-09-28 08:01:54.010869+00
2e63d1f6-39ae-4720-9e7a-4fc3e9f64d5e	90b8631a-dba0-43a1-b722-92176fd4bd13	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	Approve	\N	\N	2026-09-28 08:01:54.808251+00
e05c4d38-31a7-4bb9-ac92-fc91a25c1904	c00848c0-50fa-4a02-bcf8-e7967c9a92c9	083ecfe5-aa01-4703-9168-762f0065078f	Reject	\N	changed my mind	2026-09-28 08:02:00.338606+00
52692955-461b-4e60-824c-70d09a9b9db7	9534f3f0-685a-4450-bfc0-983f2d16f7d9	083ecfe5-aa01-4703-9168-762f0065078f	ApproveWithConditions	Annual on-site audit of the vendor; PII encrypted at rest	\N	2026-09-28 08:02:04.057771+00
3a727d50-e5b6-49b6-af29-00c92226ea6e	9534f3f0-685a-4450-bfc0-983f2d16f7d9	fa142c1c-58cc-4666-b135-7768a2ab33f0	Approve	\N	\N	2026-09-28 08:02:04.514087+00
a977d8b1-462b-4304-b533-b031697ebe7c	fe6f95b7-3a35-4799-9eb2-e3239a6a3674	083ecfe5-aa01-4703-9168-762f0065078f	ApproveWithConditions	Annual on-site audit of the vendor; cardholder PII encrypted at rest (QA)	\N	2026-09-28 08:08:03.996253+00
460e2d3d-9500-498b-929a-bdfad398726e	fe6f95b7-3a35-4799-9eb2-e3239a6a3674	fa142c1c-58cc-4666-b135-7768a2ab33f0	Approve	\N	\N	2026-09-28 08:08:09.643373+00
73d482ab-ef38-415f-bc9e-72967153175c	eb5c9dbb-e31b-4d8b-8820-d13aa90fabc1	083ecfe5-aa01-4703-9168-762f0065078f	Approve	\N	\N	2026-09-29 17:43:17.68689+00
d7c27797-bfdf-4d0c-a92c-c35fffdebe7c	eb5c9dbb-e31b-4d8b-8820-d13aa90fabc1	fa142c1c-58cc-4666-b135-7768a2ab33f0	Approve	\N	\N	2026-09-29 17:43:44.545607+00
2ea2d8a2-0d00-4606-a69e-b07f641f9c74	6e3cb87c-89cf-41ae-9629-15e5ae88b2ca	083ecfe5-aa01-4703-9168-762f0065078f	Approve	\N	\N	2026-09-30 13:04:53.589426+00
ce6878ba-bc6c-4b38-8e90-0ee7588c2552	b2a913c6-c962-4dfd-9961-810e58affc32	083ecfe5-aa01-4703-9168-762f0065078f	ApproveWithConditions	QA-FT 05Oct conditions: quarterly review of prepaid reload limits; enhanced monitoring for cross-border loads	\N	2026-10-05 09:29:28.909751+00
6fc78b7e-bb68-46f6-aac9-1fff11930f2f	b2a913c6-c962-4dfd-9961-810e58affc32	fa142c1c-58cc-4666-b135-7768a2ab33f0	Approve	\N	\N	2026-10-05 09:30:52.73098+00
\.


--
-- Data for Name: control; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.control (id, risk_category_id, name, description, created_at) FROM stdin;
f2e10b03-e672-42da-9295-9093b5a6fd84	22222222-2222-2222-2222-222222222221	Wire transfer transaction monitoring	Automated rule-based monitoring of outbound/inbound wire transfers for structuring and high-risk counterparties.	2026-09-29 08:10:29.7646+00
c0e2f410-3642-469a-94d2-f9d8eac0b2b2	22222222-2222-2222-2222-222222222221	Trade finance dual review	Second-reviewer sign-off on trade finance instruments above a defined value threshold.	2026-09-29 08:10:29.7646+00
76333a56-763e-4ea4-938c-a97d372a91de	22222222-2222-2222-2222-222222222221	Prepaid access load limits	System-enforced daily/monthly load and reload limits on prepaid access products.	2026-09-29 08:10:29.7646+00
7ee7aaa5-4b80-4304-a149-7aa95e7c57b6	22222222-2222-2222-2222-222222222221	Correspondent banking due diligence	Periodic AML risk-rating review of correspondent banking relationships.	2026-09-29 08:10:29.7646+00
61dab720-35e5-4d77-84d4-9e3c16685c1a	22222222-2222-2222-2222-222222222222	Enhanced due diligence for PEPs	Mandatory enhanced due diligence and senior-management sign-off before onboarding a politically exposed person.	2026-09-29 08:10:29.7646+00
05cec90a-8056-4c96-b5a7-ce5b30515ae8	22222222-2222-2222-2222-222222222222	Beneficial ownership verification	Verification of beneficial ownership to the 25% threshold for legal-entity customers at onboarding.	2026-09-29 08:10:29.7646+00
f2454cd8-2368-43db-ad6d-fd797f6ffc2c	22222222-2222-2222-2222-222222222222	Cash-intensive business monitoring thresholds	Tiered transaction-monitoring thresholds calibrated to a cash-intensive business's expected activity.	2026-09-29 08:10:29.7646+00
46977ebe-4d9e-47ae-b9dc-c11f6959fafd	22222222-2222-2222-2222-222222222222	MSB registration verification	Verification of FinCEN MSB registration status prior to account opening.	2026-09-29 08:10:29.7646+00
af3a916f-bd80-46ed-9589-2f482e6a2b57	22222222-2222-2222-2222-222222222223	OFAC sanctions screening	Real-time screening of parties and transactions against OFAC and other sanctions lists.	2026-09-29 08:10:29.7646+00
bfb124c8-b49b-442b-919a-f410b62d5101	22222222-2222-2222-2222-222222222223	FATF high-risk jurisdiction escalation	Automatic escalation to FCRM review for activity involving a FATF high-risk or monitored jurisdiction.	2026-09-29 08:10:29.7646+00
c83df816-82d3-4576-b22c-965d468654cb	22222222-2222-2222-2222-222222222223	Geographic risk scoring model	Country-level risk scoring feeding into customer and transaction risk ratings.	2026-09-29 08:10:29.7646+00
134c6c17-3a8f-43a0-8627-db01502a319a	22222222-2222-2222-2222-222222222224	Non-face-to-face identity verification	Documentary and non-documentary identity verification for online/non-face-to-face account opening.	2026-09-29 08:10:29.7646+00
daa753d3-033f-40b1-b1f7-3576ff69a671	22222222-2222-2222-2222-222222222224	Third-party agent oversight program	Periodic audit and monitoring of third-party agents acting on the bank's behalf.	2026-09-29 08:10:29.7646+00
d75129ca-6715-4909-be7c-1751bb9e5785	22222222-2222-2222-2222-222222222224	Correspondent relationship due diligence	Due diligence on the delivery-channel risk of correspondent banking relationships.	2026-09-29 08:10:29.7646+00
\.


--
-- Data for Name: extracted_field; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.extracted_field (id, change_request_id, attachment_id, field_key, field_value, confidence, needs_review, source_excerpt, source, updated_by_user_id, updated_at) FROM stdin;
9bc6209e-b918-44e8-bb93-4bda2e6a131c	87057aee-66d0-4eed-b503-ee593be28113	d0e2c4f6-3ecf-4088-bc65-aa0eb0ee5528	vendor_name	QuickPay Processing LLC	1.000	f	Vendor: QuickPay Processing LLC	AiExtracted	\N	2026-09-22 15:39:44.459448+00
c324f74f-4f37-4698-8e50-1dd81d933e18	87057aee-66d0-4eed-b503-ee593be28113	d0e2c4f6-3ecf-4088-bc65-aa0eb0ee5528	vendor_jurisdiction	Cayman Islands	1.000	f	Jurisdiction: Cayman Islands	AiExtracted	\N	2026-09-22 15:39:44.834102+00
e95fdbbc-d490-456e-99c8-cf23d29734c7	87057aee-66d0-4eed-b503-ee593be28113	d0e2c4f6-3ecf-4088-bc65-aa0eb0ee5528	data_access_scope	Full transaction data, card PANs, and cardholder PII	\N	f	Data access scope: Full transaction data, card PANs	AnalystCorrected	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-22 15:40:27.619131+00
c748243e-9efe-4bcb-bd3d-cab8c94b42c3	89313b30-9064-4caa-8838-29e42ddc72f2	7ccdf7d2-288f-4a80-833f-4720064f1d5f	vendor_jurisdiction	Malta	1.000	f	Jurisdiction: Malta	AiExtracted	\N	2026-09-25 06:54:08.94276+00
b8c66dd3-ce46-432f-88c9-72bd11869b8f	89313b30-9064-4caa-8838-29e42ddc72f2	7ccdf7d2-288f-4a80-833f-4720064f1d5f	data_access_scope	cardholder PII and settlement files	1.000	f	Data access scope: cardholder PII and settlement files	AiExtracted	\N	2026-09-25 06:54:08.975603+00
4a3e6781-c5b4-4a79-88cd-82a698b68ad9	89313b30-9064-4caa-8838-29e42ddc72f2	7ccdf7d2-288f-4a80-833f-4720064f1d5f	customer_types_affected	retail cardholders, MSB merchants	1.000	f	Customer types affected: retail cardholders, MSB merchants	AiExtracted	\N	2026-09-25 06:54:09.007583+00
c93aa97d-143a-46b3-b643-4a8b255d93f6	89313b30-9064-4caa-8838-29e42ddc72f2	7ccdf7d2-288f-4a80-833f-4720064f1d5f	delivery_channel	API, non-face-to-face	1.000	f	Delivery channel: API, non-face-to-face	AiExtracted	\N	2026-09-25 06:54:09.040168+00
8a9bac73-2605-415d-9718-50cb9f3cfd56	89313b30-9064-4caa-8838-29e42ddc72f2	7ccdf7d2-288f-4a80-833f-4720064f1d5f	vendor_name	QA corrected value	\N	f	Vendor name: QuickPay Processing Ltd	AnalystCorrected	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 06:54:10.8808+00
ffe73d55-3ab5-451d-b66d-8e6e0d8acfbc	298d4e01-a257-407a-9f27-04b96c02ff54	b95d8cc7-a14f-4176-b87a-56d9a8072f03	vendor_jurisdiction	Malta	1.000	f	Jurisdiction: Malta	AiExtracted	\N	2026-09-25 06:59:04.132252+00
6899e3d3-b69b-4c61-8c6c-a63acdc86510	298d4e01-a257-407a-9f27-04b96c02ff54	b95d8cc7-a14f-4176-b87a-56d9a8072f03	data_access_scope	cardholder PII and settlement files	1.000	f	Data access scope: cardholder PII and settlement files	AiExtracted	\N	2026-09-25 06:59:04.165023+00
cde677eb-70dd-4cde-a479-fbeee148b1e2	298d4e01-a257-407a-9f27-04b96c02ff54	b95d8cc7-a14f-4176-b87a-56d9a8072f03	customer_types_affected	retail cardholders, MSB merchants	1.000	f	Customer types affected: retail cardholders, MSB merchants	AiExtracted	\N	2026-09-25 06:59:04.197314+00
317f2c4f-28ef-4d27-81bf-4c893e91637a	298d4e01-a257-407a-9f27-04b96c02ff54	b95d8cc7-a14f-4176-b87a-56d9a8072f03	delivery_channel	API, non-face-to-face	1.000	f	Delivery channel: API, non-face-to-face	AiExtracted	\N	2026-09-25 06:59:04.231569+00
d079bc02-c970-4eda-aed6-56f3f94f0bec	617f16d3-e50b-487c-a31d-cedbbc7b572a	d9da15e7-6334-4e80-8024-90c0234ef226	vendor_name	QA corrected value	\N	f	Vendor name: QuickPay Processing Ltd	AnalystCorrected	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-28 08:01:09.158672+00
3bf273f8-0362-4116-a5da-abf04f732ac6	298d4e01-a257-407a-9f27-04b96c02ff54	b95d8cc7-a14f-4176-b87a-56d9a8072f03	vendor_name	QA corrected value	\N	f	Vendor name: QuickPay Processing Ltd	AnalystCorrected	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 06:59:05.944154+00
6c02deaf-9b1c-47ed-b377-c781a4e508c9	ef797803-aaf9-4a7a-b7af-a86f6f010f9a	bec64b5e-fcf3-4dfb-9805-490a757c5a5c	vendor_jurisdiction	Malta	1.000	f	Jurisdiction: Malta	AiExtracted	\N	2026-09-25 07:22:49.306233+00
77882651-65c8-49d0-b0aa-9e7fe938daee	ef797803-aaf9-4a7a-b7af-a86f6f010f9a	bec64b5e-fcf3-4dfb-9805-490a757c5a5c	data_access_scope	cardholder PII and settlement files	1.000	f	Data access scope: cardholder PII and settlement files	AiExtracted	\N	2026-09-25 07:22:49.338997+00
477bd9fe-ca0e-4e34-b2b7-018adf0f114c	ef797803-aaf9-4a7a-b7af-a86f6f010f9a	bec64b5e-fcf3-4dfb-9805-490a757c5a5c	customer_types_affected	retail cardholders, MSB merchants	1.000	f	Customer types affected: retail cardholders, MSB merchants	AiExtracted	\N	2026-09-25 07:22:49.371374+00
85804a91-c955-43d2-a964-1f0273b36ce1	ef797803-aaf9-4a7a-b7af-a86f6f010f9a	bec64b5e-fcf3-4dfb-9805-490a757c5a5c	delivery_channel	API, non-face-to-face	1.000	f	Delivery channel: API, non-face-to-face	AiExtracted	\N	2026-09-25 07:22:49.40569+00
c6640e81-9700-45a5-b538-fdf7511ed13a	a6bbfac6-7b11-45b5-8c48-74c1efc1a343	f81b2017-2a58-4223-9909-bcf0f23738ba	vendor_name	\N	0.000	t	vendor-due-diligence.pdf	AiExtracted	\N	2026-09-28 08:06:00.140989+00
f6778bcd-f06c-457f-ab03-3bba2471ec7f	ef797803-aaf9-4a7a-b7af-a86f6f010f9a	bec64b5e-fcf3-4dfb-9805-490a757c5a5c	vendor_name	QA corrected value	\N	f	Vendor name: QuickPay Processing Ltd	AnalystCorrected	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-25 07:22:51.402529+00
cbe140ca-c6dc-4bfc-9c59-a71957b45263	846abe95-3e9a-438f-9b30-0c7097371a27	17b2efa1-50d9-47e5-80af-b905522d548a	product_name	Prepaid Settlement Card	1.000	f	Product Launch Brief - Prepaid Settlement Card	AiExtracted	\N	2026-09-30 12:22:22.804245+00
0ca0fbe4-5920-4acd-b8d4-093d4af88538	507e6f32-ab80-40db-81bd-5f641ef033a4	00081c88-4365-4838-a6c0-96bc9b7b5258	vendor_name	QuickPay Processing Ltd.	1.000	f	Vendor name: QuickPay Processing Ltd.	AiExtracted	\N	2026-09-25 07:34:08.71853+00
3964b793-9844-4c59-9555-d82628155a87	507e6f32-ab80-40db-81bd-5f641ef033a4	00081c88-4365-4838-a6c0-96bc9b7b5258	vendor_jurisdiction	Malta	1.000	f	Jurisdiction: Malta.	AiExtracted	\N	2026-09-25 07:34:08.757853+00
54b8f8c2-aee1-46a9-82e8-75b5ebe87481	507e6f32-ab80-40db-81bd-5f641ef033a4	00081c88-4365-4838-a6c0-96bc9b7b5258	data_access_scope	cardholder PII and settlement files	1.000	f	Data access scope: cardholder PII and settlement files.	AiExtracted	\N	2026-09-25 07:34:08.792632+00
5a1fbad3-bea1-44ea-b955-0f974638ae37	846abe95-3e9a-438f-9b30-0c7097371a27	17b2efa1-50d9-47e5-80af-b905522d548a	product_description	A reloadable prepaid debit card issued to retail and small-business customers, enabling domestic and cross-border point-of-sale and ATM transactions.	1.000	f	A reloadable prepaid debit card issued to retail and small-business customers,enabling domestic and cross-border point-of-sale and ATM transactions.	AiExtracted	\N	2026-09-30 12:22:23.24706+00
e3d69ed2-16fa-41c0-82e7-12aa97bc8f03	617f16d3-e50b-487c-a31d-cedbbc7b572a	d9da15e7-6334-4e80-8024-90c0234ef226	vendor_jurisdiction	Malta	1.000	f	Jurisdiction: Malta	AiExtracted	\N	2026-09-28 08:01:07.330827+00
20244ea1-a869-4344-8084-8be6bdaa40c8	617f16d3-e50b-487c-a31d-cedbbc7b572a	d9da15e7-6334-4e80-8024-90c0234ef226	data_access_scope	cardholder PII and settlement files	1.000	f	Data access scope: cardholder PII and settlement files	AiExtracted	\N	2026-09-28 08:01:07.369108+00
e207ff50-94da-4604-a04c-f9ba7dc3ec8c	617f16d3-e50b-487c-a31d-cedbbc7b572a	d9da15e7-6334-4e80-8024-90c0234ef226	customer_types_affected	retail cardholders, MSB merchants	1.000	f	Customer types affected: retail cardholders, MSB merchants	AiExtracted	\N	2026-09-28 08:01:07.407122+00
41f2319d-4ef4-4e93-bfe4-d477daae46a3	617f16d3-e50b-487c-a31d-cedbbc7b572a	d9da15e7-6334-4e80-8024-90c0234ef226	delivery_channel	API, non-face-to-face	1.000	f	Delivery channel: API, non-face-to-face	AiExtracted	\N	2026-09-28 08:01:07.450071+00
9d9b81fd-a7a8-45fb-be85-165abf747a7d	846abe95-3e9a-438f-9b30-0c7097371a27	17b2efa1-50d9-47e5-80af-b905522d548a	target_customers	Retail consumers and cash-intensive small businesses (e.g. retail shops, restaurants)	1.000	f	Target customers: Retail consumers and cash-intensive small businesses (e.g. retail shops, restaurants)	AiExtracted	\N	2026-09-30 12:22:23.57541+00
1c0eec56-bbb9-462b-b56c-22e35eebef1f	846abe95-3e9a-438f-9b30-0c7097371a27	17b2efa1-50d9-47e5-80af-b905522d548a	excluded_customer_types	No PEP or NRA customers targeted at launch	1.000	f	No PEP or NRA customers targeted at launch.	AiExtracted	\N	2026-09-30 12:22:23.904359+00
fc3e7458-dda1-426d-bcc5-ac421e57eb0c	846abe95-3e9a-438f-9b30-0c7097371a27	17b2efa1-50d9-47e5-80af-b905522d548a	transaction_types	Card-present point-of-sale, ATM withdrawal, and card-not-present online transactions	1.000	f	Transaction types: Card-present point-of-sale, ATM withdrawal, and card-not-present online transactions.	AiExtracted	\N	2026-09-30 12:22:24.32362+00
c0928ba1-143f-47df-b681-5dc42349ee68	846abe95-3e9a-438f-9b30-0c7097371a27	17b2efa1-50d9-47e5-80af-b905522d548a	cross_border_transaction_coverage	Cross-border transactions supported in 12 countries including two FATF-monitored jurisdictions	1.000	f	Cross-border transactions supported in 12 countries including two FATF-monitored jurisdictions.	AiExtracted	\N	2026-09-30 12:22:24.743151+00
d60945d4-65cb-4c76-a886-4250224e7ba7	846abe95-3e9a-438f-9b30-0c7097371a27	17b2efa1-50d9-47e5-80af-b905522d548a	onboarding_channel	Fully online (non-face-to-face) enrollment via mobile app; no branch visit required	1.000	f	Onboarding channel: Fully online (non-face-to-face) enrollment via mobile app; no branch visit required.	AiExtracted	\N	2026-09-30 12:22:25.063849+00
f42ef83b-8108-47a6-b87c-d00f146dbad7	846abe95-3e9a-438f-9b30-0c7097371a27	17b2efa1-50d9-47e5-80af-b905522d548a	third_party_processors	QuickPay Processing Ltd	1.000	f	Third parties: Card processing handled by an external payment processor (QuickPay Processing Ltd)	AiExtracted	\N	2026-09-30 12:22:25.379271+00
552c205c-267b-45ce-9386-00deabc8299e	846abe95-3e9a-438f-9b30-0c7097371a27	17b2efa1-50d9-47e5-80af-b905522d548a	data_handled	Cardholder PII (name, address, SSN last-4), transaction history, device fingerprint	1.000	f	Data handled: Cardholder PII (name, address, SSN last-4), transaction history, device fingerprint.	AiExtracted	\N	2026-09-30 12:22:26.038845+00
4765ead5-6ed3-4825-ac65-4c0f4938e41c	846abe95-3e9a-438f-9b30-0c7097371a27	17b2efa1-50d9-47e5-80af-b905522d548a	third_party_data_exchange_method	SFTP-based daily settlement file exchange (not real-time API)	\N	f	with API-based daily settlement file exchange.	AnalystCorrected	4fa322d3-2245-44ef-b664-1a804442db23	2026-09-30 12:29:14.792767+00
\.


--
-- Data for Name: policy_chunk; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.policy_chunk (id, policy_document_id, risk_category_id, section_ref, chunk_text, created_at) FROM stdin;
3f171e93-f2ca-40a4-af6a-18ede9021c9b	33333333-3333-3333-3333-333333333331	22222222-2222-2222-2222-222222222221	Risks Associated with Money Laundering and Terrorist Financing - Products and Services	Certain products and services are inherently vulnerable to money laundering because they involve rapid movement of funds or limited face-to-face contact, including electronic funds transfers, correspondent banking, private banking, trade finance, and prepaid access products. Examiners assess whether a bank has identified, measured, and mitigated the risks these offerings present before launch.	2026-09-22 13:52:15.218393+00
8fc9b915-62af-410e-af73-373e51aac522	33333333-3333-3333-3333-333333333331	22222222-2222-2222-2222-222222222221	Risks Associated with Money Laundering and Terrorist Financing - Correspondent Banking	Correspondent accounts, particularly those for foreign financial institutions, can expose a bank to the risks of the respondent's own customer base and the adequacy of its AML controls. Enhanced due diligence is expected for correspondent relationships involving higher-risk jurisdictions or nested account arrangements.	2026-09-22 13:52:15.218393+00
e7a09ebd-9c1f-4779-8499-fa131c4a77c4	33333333-3333-3333-3333-333333333331	22222222-2222-2222-2222-222222222222	Risks Associated with Money Laundering and Terrorist Financing - Customers	Certain categories of customers and entities pose elevated money laundering risk, including cash-intensive businesses, money services businesses, non-resident aliens, politically exposed persons, and non-governmental organizations operating in higher-risk sectors. A risk-based customer due diligence program should scale scrutiny to the customer's risk profile.	2026-09-22 13:52:15.218393+00
af07f40f-b9fa-4614-891b-b0fcc9a8f54b	33333333-3333-3333-3333-333333333331	22222222-2222-2222-2222-222222222222	Risks Associated with Money Laundering and Terrorist Financing - Beneficial Ownership	Legal entity customers with complex or opaque ownership structures, including shell companies, can be used to obscure the identity of beneficial owners. Banks are expected to identify and verify beneficial owners holding a defined ownership threshold as part of customer due diligence.	2026-09-22 13:52:15.218393+00
79e625c1-e99c-43d0-9c93-4f2ee8b6f914	33333333-3333-3333-3333-333333333331	22222222-2222-2222-2222-222222222223	Risks Associated with Money Laundering and Terrorist Financing - Geographic Locations	Geographic risk considers a bank's exposure to jurisdictions identified by FATF as having strategic AML/CFT deficiencies, countries subject to OFAC sanctions programs, and domestic High Intensity Financial Crime Areas (HIFCAs). Products, customers, and transactions tied to these locations warrant additional scrutiny.	2026-09-22 13:52:15.218393+00
539e307e-5d18-454b-a33c-fbcf3ff8c407	33333333-3333-3333-3333-333333333331	22222222-2222-2222-2222-222222222224	Risks Associated with Money Laundering and Terrorist Financing - Delivery Channels	Non-face-to-face account opening and transaction channels, including online and mobile banking, and reliance on third-party agents or correspondent relationships to deliver products, reduce a bank's ability to verify customer identity and intent directly, and should be factored into the overall risk assessment of a proposed change.	2026-09-22 13:52:15.218393+00
d94818e8-9c02-4bc8-ae95-57f8e08beec8	33333333-3333-3333-3333-333333333331	22222222-2222-2222-2222-222222222221	Risks Associated with Money Laundering and Terrorist Financing - Wire Transfers	Wire transfers permit the rapid movement of funds between banks domestically and internationally and are a common vehicle for laundering illicit proceeds. A bank should retain complete originator and beneficiary information on wire transfers, screen transfers against sanctions lists, and apply enhanced scrutiny to wire activity that is inconsistent with a customer's stated business or expected transaction profile.	2026-09-29 08:10:31.92963+00
607d5286-7adc-4312-a1e9-7e3edce1d27a	33333333-3333-3333-3333-333333333331	22222222-2222-2222-2222-222222222221	Risks Associated with Money Laundering and Terrorist Financing - Automated Clearing House	Automated Clearing House (ACH) transactions, particularly third-party payment processor relationships, can be used to originate a high volume of low-dollar transactions that individually evade scrutiny. A bank offering ACH origination services should understand the nature of the underlying payments being processed on its behalf.	2026-09-29 08:10:31.92963+00
95bcea5f-6600-4d8f-8f45-69339fa43259	33333333-3333-3333-3333-333333333331	22222222-2222-2222-2222-222222222221	Risks Associated with Money Laundering and Terrorist Financing - Private Banking	Private banking relationships often involve higher-net-worth customers, complex account structures, and a greater expectation of confidentiality, all of which can be exploited to obscure the source of funds. Enhanced due diligence, including identification of the source of wealth, is expected for private banking customers.	2026-09-29 08:10:31.92963+00
4f51dd86-f2b8-41c7-88ad-2d44e8a295c2	33333333-3333-3333-3333-333333333331	22222222-2222-2222-2222-222222222222	Risks Associated with Money Laundering and Terrorist Financing - Sanctions Screening of Customers	A bank's customer due diligence program should include screening of new and existing customers against OFAC's Specially Designated Nationals list and other applicable sanctions lists at onboarding and on an ongoing basis, with a documented process for resolving potential matches before an account is opened or a transaction is processed.	2026-09-29 08:10:31.92963+00
4a27362f-c3e9-48a6-8e7d-538ca56e56a3	33333333-3333-3333-3333-333333333331	22222222-2222-2222-2222-222222222222	Risks Associated with Money Laundering and Terrorist Financing - Prepaid Access Customers	Prepaid access products sold or distributed to customers, including general-purpose reloadable cards, can be used to structure funds below reporting thresholds or move value with limited identity verification. A bank should apply customer due diligence proportionate to the funding, reload, and redemption features offered.	2026-09-29 08:10:31.92963+00
fe671133-a4bf-4fd4-8aab-2d36c733c649	33333333-3333-3333-3333-333333333331	22222222-2222-2222-2222-222222222223	Risks Associated with Money Laundering and Terrorist Financing - High-Risk Jurisdictions	A bank should identify customers, products, and transactions connected to a high-risk jurisdiction, including a country identified by FATF as having strategic AML/CFT deficiencies, before establishing or continuing the relationship, and apply enhanced due diligence commensurate with the jurisdiction's risk profile.	2026-09-29 08:10:31.92963+00
8bb4face-2391-4313-91d4-521ccbea2fdc	33333333-3333-3333-3333-333333333331	22222222-2222-2222-2222-222222222223	Risks Associated with Money Laundering and Terrorist Financing - OFAC Sanctioned Countries	Transactions or relationships involving a country subject to a comprehensive OFAC sanctions program are generally prohibited absent a specific license, and a bank should have controls in place to identify and block such activity before it settles.	2026-09-29 08:10:31.92963+00
11e99b0a-4ae9-4038-b78c-5dcb82e529af	33333333-3333-3333-3333-333333333331	22222222-2222-2222-2222-222222222223	Risks Associated with Money Laundering and Terrorist Financing - Domestic High Intensity Financial Crime Areas	Domestic High Intensity Financial Crime Areas (HIFCAs) are geographic regions designated for concentrated law enforcement attention because of elevated money laundering activity; a bank with a significant footprint in a HIFCA should factor that geographic concentration into its overall risk assessment.	2026-09-29 08:10:31.92963+00
09f2017e-b5bc-4d9d-ac1c-4fa38d5fbcbf	33333333-3333-3333-3333-333333333331	22222222-2222-2222-2222-222222222224	Risks Associated with Money Laundering and Terrorist Financing - Third-Party Agents	A bank that relies on third-party agents to open accounts or process transactions on its behalf should conduct due diligence on the agent, monitor the agent's activity, and periodically audit the agent's compliance with the bank's AML program, since the delivery channel itself does not reduce the bank's own compliance obligations.	2026-09-29 08:10:31.92963+00
\.


--
-- Data for Name: policy_document; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.policy_document (id, risk_framework_id, title, source_url, effective_date, version_label, created_at) FROM stdin;
33333333-3333-3333-3333-333333333331	11111111-1111-1111-1111-111111111111	FFIEC BSA/AML Examination Manual	https://bsaaml.ffiec.gov	2014-01-01	2014 ed.	2026-09-22 13:52:15.218393+00
\.


--
-- Data for Name: risk_category; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.risk_category (id, risk_framework_id, code, name, citation_section, created_at) FROM stdin;
22222222-2222-2222-2222-222222222221	11111111-1111-1111-1111-111111111111	PRODUCTS_SERVICES	Products & Services	FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Products and Services	2026-09-22 13:52:15.218393+00
22222222-2222-2222-2222-222222222222	11111111-1111-1111-1111-111111111111	CUSTOMERS_ENTITIES	Customers & Entities	FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Customers	2026-09-22 13:52:15.218393+00
22222222-2222-2222-2222-222222222223	11111111-1111-1111-1111-111111111111	GEOGRAPHIC_LOCATIONS	Geographic Locations	FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Geographic Locations	2026-09-22 13:52:15.218393+00
22222222-2222-2222-2222-222222222224	11111111-1111-1111-1111-111111111111	DELIVERY_CHANNELS	Delivery Channels	FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Products and Services (Delivery Channels)	2026-09-22 13:52:15.218393+00
\.


--
-- Data for Name: risk_framework; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.risk_framework (id, name, citation_source, created_at) FROM stdin;
11111111-1111-1111-1111-111111111111	FFIEC BSA/AML Examination Manual	FFIEC BSA/AML Examination Manual (bsaaml.ffiec.gov)	2026-09-22 13:52:15.218393+00
\.


--
-- Data for Name: risk_subfactor; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.risk_subfactor (id, risk_category_id, name, created_at) FROM stdin;
ff9d12c1-7212-440b-a443-80f69002847e	22222222-2222-2222-2222-222222222221	ACH	2026-09-22 13:52:15.218393+00
9865ad27-91b8-458d-9df2-19360c0fc83c	22222222-2222-2222-2222-222222222221	Wire transfers	2026-09-22 13:52:15.218393+00
b3e9521c-13c3-45af-9276-0452b6ffd8d1	22222222-2222-2222-2222-222222222221	Foreign exchange	2026-09-22 13:52:15.218393+00
1acfac8b-c642-4b7b-ac17-3e74dfb438a8	22222222-2222-2222-2222-222222222221	Trade finance	2026-09-22 13:52:15.218393+00
b21a5bac-4105-4313-a947-59315a861f8e	22222222-2222-2222-2222-222222222221	Private banking	2026-09-22 13:52:15.218393+00
dc832319-fbcb-4287-bdb6-e8c621054772	22222222-2222-2222-2222-222222222221	Prepaid access	2026-09-22 13:52:15.218393+00
9317e945-825b-410e-92e9-192e2b4dcbd0	22222222-2222-2222-2222-222222222221	Correspondent banking	2026-09-22 13:52:15.218393+00
e3ba8626-8d7e-4724-a0f0-7905770950ee	22222222-2222-2222-2222-222222222222	Cash-intensive businesses	2026-09-22 13:52:15.218393+00
eb7a52b9-fcd0-4aad-9e77-7a385ab07b05	22222222-2222-2222-2222-222222222222	Politically exposed persons (PEPs)	2026-09-22 13:52:15.218393+00
d06dcd5d-8751-4d4e-a1e9-608c870f72d0	22222222-2222-2222-2222-222222222222	Non-resident aliens	2026-09-22 13:52:15.218393+00
59d9a356-8df5-46b0-bead-ecf983fc77d7	22222222-2222-2222-2222-222222222222	Money services businesses (MSBs)	2026-09-22 13:52:15.218393+00
5dfb97f7-a3d5-4184-a0f5-d0adac9cf7b9	22222222-2222-2222-2222-222222222222	NGOs / charities	2026-09-22 13:52:15.218393+00
887b4d46-dd5e-4ea6-99a8-c6ce6196aff8	22222222-2222-2222-2222-222222222222	Shell companies	2026-09-22 13:52:15.218393+00
f9039092-6a30-492b-a9e0-7e23a46ecd50	22222222-2222-2222-2222-222222222222	Beneficial ownership complexity	2026-09-22 13:52:15.218393+00
80e91a4e-2e25-42e3-bcb4-f128ea5bc010	22222222-2222-2222-2222-222222222223	FATF high-risk / monitored jurisdictions	2026-09-22 13:52:15.218393+00
7d36be02-855c-49b9-b129-81539eb7ce07	22222222-2222-2222-2222-222222222223	OFAC sanctioned countries	2026-09-22 13:52:15.218393+00
d850158b-5e29-43ee-8e9c-4fa03044faa5	22222222-2222-2222-2222-222222222223	Domestic HIFCAs	2026-09-22 13:52:15.218393+00
c19cbf1d-e485-4d25-8bc7-cd61c9a69a55	22222222-2222-2222-2222-222222222224	In-person / branch	2026-09-22 13:52:15.218393+00
aa093872-b5fc-479f-b12b-da46b302c31b	22222222-2222-2222-2222-222222222224	Online / non-face-to-face	2026-09-22 13:52:15.218393+00
353a5cd6-bd70-4232-8134-478c0a89ad0a	22222222-2222-2222-2222-222222222224	Third-party agents	2026-09-22 13:52:15.218393+00
18afbe6e-af4c-40b1-9e97-1ca6db0426ad	22222222-2222-2222-2222-222222222224	Correspondent relationships	2026-09-22 13:52:15.218393+00
\.


--
-- Data for Name: schema_migrations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.schema_migrations (filename, applied_at) FROM stdin;
0001_def007_assessment_drop_scoring_config_version.sql	2026-09-29 08:05:56.934985+00
0002_def032_policy_chunk_unique_section_ref.sql	2026-09-29 08:05:58.164701+00
0003_def011_policy_reliance_risk_category_key.sql	2026-09-29 08:05:59.379259+00
0004_def013_control_unique_name.sql	2026-09-29 08:06:00.756635+00
0005_def030_committee_vote_stricter_checks.sql	2026-09-29 08:09:54.064398+00
0006_def012_vendor_delivery_channels_weight_fix.sql	2026-09-29 08:09:55.339196+00
0007_def030_restore_committee_vote_value_check.sql	2026-09-29 08:42:53.815196+00
0008_epic19_sla_tracking.sql	2026-10-05 17:06:12.577793+00
0008_epic11_app_user_multirole.sql	2026-10-07 14:32:50.246647+00
0009_admin_users_nullable_auth0_subject.sql	2026-10-07 14:32:51.546368+00
0010_epic19_sla_tracking.sql	2026-10-07 14:32:53.095698+00
\.


--
-- Data for Name: scoring_config; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.scoring_config (id, risk_category_id, max_mitigation_factor, is_active, created_by_user_id, reason, created_at) FROM stdin;
4ed29b56-c391-436d-b996-19a2ff6fdf67	22222222-2222-2222-2222-222222222224	0.850	t	374a3158-6dfa-41f2-9a4d-3d1091dffacf	Initial MVP default - see docs/architecture/architecture-mapping.md	2026-09-22 13:52:15.218393+00
bf22f802-8714-4937-8026-ec70dbec3d71	22222222-2222-2222-2222-222222222221	0.850	t	374a3158-6dfa-41f2-9a4d-3d1091dffacf	Initial MVP default - see docs/architecture/architecture-mapping.md	2026-09-22 13:52:15.218393+00
3e2165c9-7c7b-4c9d-b5ab-7973008adecd	22222222-2222-2222-2222-222222222223	0.850	t	374a3158-6dfa-41f2-9a4d-3d1091dffacf	Initial MVP default - see docs/architecture/architecture-mapping.md	2026-09-22 13:52:15.218393+00
d1ba19d8-3cc8-4604-b0af-ca367901eb07	22222222-2222-2222-2222-222222222222	0.850	f	374a3158-6dfa-41f2-9a4d-3d1091dffacf	Initial MVP default - see docs/architecture/architecture-mapping.md	2026-09-22 13:52:15.218393+00
dc972259-9776-40dd-8fe9-c65b6876723d	22222222-2222-2222-2222-222222222222	0.800	f	374a3158-6dfa-41f2-9a4d-3d1091dffacf	QA: in-flight isolation test (restored immediately)	2026-09-25 07:02:21.444592+00
3046cd30-9350-4d96-a213-0bd2e0286009	22222222-2222-2222-2222-222222222222	0.850	f	374a3158-6dfa-41f2-9a4d-3d1091dffacf	QA: restore baseline after TC-API-102	2026-09-25 07:02:22.119103+00
18faae4c-c654-4a76-9b9e-0569edb869d9	22222222-2222-2222-2222-222222222222	0.850	f	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	QA: RBAC probe - value unchanged	2026-09-25 07:02:32.691881+00
64715f64-1a26-4179-a75b-0120f9f7c0cf	22222222-2222-2222-2222-222222222222	0.850	f	374a3158-6dfa-41f2-9a4d-3d1091dffacf	QA: re-save unchanged baseline	2026-09-25 07:20:17.960013+00
7a8c96fc-08c4-4f33-bcbc-ce10574ba2e0	22222222-2222-2222-2222-222222222222	0.800	f	374a3158-6dfa-41f2-9a4d-3d1091dffacf	QA: in-flight isolation test (restored immediately)	2026-09-25 07:23:48.048137+00
2e831d36-94a8-4df9-96fd-a903a9326736	22222222-2222-2222-2222-222222222222	0.850	f	374a3158-6dfa-41f2-9a4d-3d1091dffacf	QA: restore baseline after TC-API-102	2026-09-25 07:23:48.705612+00
afdc6f41-3e8d-469d-8242-f66632b86bd3	22222222-2222-2222-2222-222222222222	0.850	f	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	QA: RBAC probe - value unchanged	2026-09-25 07:23:59.835263+00
e541d012-e837-480a-9184-c5b8c221d406	22222222-2222-2222-2222-222222222222	0.850	f	374a3158-6dfa-41f2-9a4d-3d1091dffacf	QA: re-save unchanged baseline	2026-09-25 07:29:52.785235+00
8e746b29-2cb4-4d95-b1df-652b1e30ed44	22222222-2222-2222-2222-222222222222	0.800	f	374a3158-6dfa-41f2-9a4d-3d1091dffacf	QA: in-flight isolation test (restored immediately)	2026-09-28 08:02:14.977569+00
1830ad2f-5abd-463a-a291-7d9e399632f6	22222222-2222-2222-2222-222222222222	0.850	f	374a3158-6dfa-41f2-9a4d-3d1091dffacf	QA: restore baseline after TC-API-102	2026-09-28 08:02:15.645747+00
4ecf4722-7cc2-4d06-91e9-7bca8133a76e	22222222-2222-2222-2222-222222222222	0.850	f	a6a709a7-65e7-4a90-9b58-cbbaec1d651a	QA: RBAC probe - value unchanged	2026-09-28 08:02:28.788005+00
6a62e7ad-be7f-4246-9f2f-7611b24fd97a	22222222-2222-2222-2222-222222222222	0.850	f	374a3158-6dfa-41f2-9a4d-3d1091dffacf	QA: re-save unchanged baseline	2026-09-28 08:08:36.76768+00
7350651e-ef4f-4e18-9f91-ce93c127f47c	22222222-2222-2222-2222-222222222222	0.800	f	374a3158-6dfa-41f2-9a4d-3d1091dffacf	QA-FT 05Oct TC-CFG-01: tighten Customers & Entities cap to 0.80 (restored after test)	2026-10-05 09:38:43.86919+00
7697af84-945b-4d44-89a8-1a3c8dcb8b2e	22222222-2222-2222-2222-222222222222	0.850	t	374a3158-6dfa-41f2-9a4d-3d1091dffacf	QA-FT 05Oct: restore Customers & Entities cap to 0.85 after TC-CFG-01	2026-10-05 09:39:05.383305+00
\.


--
-- Data for Name: sla_config; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.sla_config (id, version_number, at_risk_threshold_pct, pause_on_clarification, is_active, created_by_user_id, reason, created_at) FROM stdin;
b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	1	80	t	f	374a3158-6dfa-41f2-9a4d-3d1091dffacf	Initial defaults confirmed by the team, 24 Sep 2026	2026-10-05 17:07:24.427874+00
8a75bac7-b9ba-4928-a791-97e0ccefa082	2	80	t	t	374a3158-6dfa-41f2-9a4d-3d1091dffacf	Aligned to the 2-business-day decision target agreed on the 7 Oct 2026 sync-up (overall only, stage targets optional)	2026-10-07 14:06:49.635771+00
\.


--
-- Data for Name: sla_holiday; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.sla_holiday (id, holiday_date, is_active, created_by_user_id, reason, created_at) FROM stdin;
\.


--
-- Data for Name: sla_target; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.sla_target (sla_config_id, change_type, stage, target_business_days) FROM stdin;
b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	Product	Submitted	2
b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	Product	InAssessment	8
b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	Product	PendingCommittee	5
b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	Product	EndToEnd	15
b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	Feature	Submitted	2
b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	Feature	InAssessment	8
b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	Feature	PendingCommittee	5
b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	Feature	EndToEnd	15
b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	Process	Submitted	2
b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	Process	InAssessment	8
b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	Process	PendingCommittee	5
b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	Process	EndToEnd	15
b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	Vendor	Submitted	2
b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	Vendor	InAssessment	8
b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	Vendor	PendingCommittee	5
b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	Vendor	EndToEnd	15
b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	Geography	Submitted	2
b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	Geography	InAssessment	8
b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	Geography	PendingCommittee	5
b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	Geography	EndToEnd	15
b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	CustomerSegment	Submitted	2
b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	CustomerSegment	InAssessment	8
b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	CustomerSegment	PendingCommittee	5
b5fce2ab-3e01-45fa-a04c-fd83ff27f81b	CustomerSegment	EndToEnd	15
8a75bac7-b9ba-4928-a791-97e0ccefa082	Product	EndToEnd	2
8a75bac7-b9ba-4928-a791-97e0ccefa082	Feature	EndToEnd	2
8a75bac7-b9ba-4928-a791-97e0ccefa082	Process	EndToEnd	2
8a75bac7-b9ba-4928-a791-97e0ccefa082	Vendor	EndToEnd	2
8a75bac7-b9ba-4928-a791-97e0ccefa082	Geography	EndToEnd	2
8a75bac7-b9ba-4928-a791-97e0ccefa082	CustomerSegment	EndToEnd	2
\.


--
-- Data for Name: workflow_rule; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.workflow_rule (id, rule_key, rule_value, is_active, created_by_user_id, reason, created_at) FROM stdin;
9d21becc-0133-4597-b199-683dbaac949e	CommitteeQuorum	{"quorum": 2}	f	374a3158-6dfa-41f2-9a4d-3d1091dffacf	Initial MVP default - see docs/architecture/architecture-mapping.md	2026-09-22 13:52:15.218393+00
d372b4da-a6d2-4921-9aba-35a17aee5055	CommitteeQuorum	{"quorum": 2}	f	374a3158-6dfa-41f2-9a4d-3d1091dffacf	QA: re-save unchanged value	2026-09-25 07:02:24.934315+00
d2418460-1ad5-418c-bc0f-aded1d1a025c	CommitteeQuorum	{"quorum": 2}	f	374a3158-6dfa-41f2-9a4d-3d1091dffacf	QA: re-save unchanged quorum	2026-09-25 07:20:12.71744+00
a3000747-47f1-4f54-94ed-fc92a4f1ddbf	CommitteeQuorum	{"quorum": 2}	f	374a3158-6dfa-41f2-9a4d-3d1091dffacf	QA: re-save unchanged value	2026-09-25 07:23:51.481005+00
070ffe5e-7463-4116-bb16-a8787417db31	CommitteeQuorum	{"quorum": 2}	f	374a3158-6dfa-41f2-9a4d-3d1091dffacf	QA: re-save unchanged quorum	2026-09-25 07:29:47.116385+00
742e09d9-5a4e-434d-ac19-004b675bc2bd	CommitteeQuorum	{"quorum": 2}	f	374a3158-6dfa-41f2-9a4d-3d1091dffacf	QA: re-save unchanged value	2026-09-28 08:02:19.022231+00
cf69adeb-1295-410f-b718-6f8df81c25ae	QA_FT_NoAuthProbe	{"probe": true}	t	374a3158-6dfa-41f2-9a4d-3d1091dffacf	QA-FT TC-ACL-01 unauthenticated write probe	2026-10-05 09:35:38.340803+00
29b2108d-a40d-4ae3-a13d-105fe74b458d	CommitteeQuorum	{"quorum": 2}	f	374a3158-6dfa-41f2-9a4d-3d1091dffacf	QA: re-save unchanged quorum	2026-09-28 08:08:30.425024+00
10ffc9e2-e8ab-429e-8e5c-295066c6d3a7	CommitteeQuorum	{"quorum": 3}	f	374a3158-6dfa-41f2-9a4d-3d1091dffacf	QA-FT 05Oct TC-CFG-03: quorum 3 (restored to 2 after test)	2026-10-05 09:39:44.368898+00
b424413e-b0bf-4728-9ae3-0dd88395d1a8	CommitteeQuorum	{"quorum": 2}	f	374a3158-6dfa-41f2-9a4d-3d1091dffacf	QA-FT 05Oct: restore quorum to 2 after TC-CFG-03	2026-10-05 09:39:49.851603+00
e4112056-e1d6-461c-be2d-654eb978e064	CommitteeQuorum	{"quorum": 2}	t	4fa322d3-2245-44ef-b664-1a804442db23	QA-FT TC-ACL-02: Analyst workflow save (must be refused)	2026-10-05 09:40:38.479899+00
\.


--
-- Name: change_request_number_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.change_request_number_seq', 106, true);


--
-- Name: core_banking_product core_banking_product_pkey; Type: CONSTRAINT; Schema: mock_systems; Owner: -
--

ALTER TABLE ONLY mock_systems.core_banking_product
    ADD CONSTRAINT core_banking_product_pkey PRIMARY KEY (id);


--
-- Name: crm_customer crm_customer_pkey; Type: CONSTRAINT; Schema: mock_systems; Owner: -
--

ALTER TABLE ONLY mock_systems.crm_customer
    ADD CONSTRAINT crm_customer_pkey PRIMARY KEY (id);


--
-- Name: vendor_registry vendor_registry_pkey; Type: CONSTRAINT; Schema: mock_systems; Owner: -
--

ALTER TABLE ONLY mock_systems.vendor_registry
    ADD CONSTRAINT vendor_registry_pkey PRIMARY KEY (id);


--
-- Name: app_user app_user_auth0_subject_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_user
    ADD CONSTRAINT app_user_auth0_subject_key UNIQUE (auth0_subject);


--
-- Name: app_user app_user_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_user
    ADD CONSTRAINT app_user_pkey PRIMARY KEY (id);


--
-- Name: app_user_role app_user_role_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_user_role
    ADD CONSTRAINT app_user_role_pkey PRIMARY KEY (user_id, role);


--
-- Name: assessment_category_mapping assessment_category_mapping_assessment_id_risk_category_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment_category_mapping
    ADD CONSTRAINT assessment_category_mapping_assessment_id_risk_category_id_key UNIQUE (assessment_id, risk_category_id);


--
-- Name: assessment_category_mapping assessment_category_mapping_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment_category_mapping
    ADD CONSTRAINT assessment_category_mapping_pkey PRIMARY KEY (id);


--
-- Name: assessment assessment_change_request_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment
    ADD CONSTRAINT assessment_change_request_id_key UNIQUE (change_request_id);


--
-- Name: assessment_narrative_section assessment_narrative_section_assessment_id_risk_category_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment_narrative_section
    ADD CONSTRAINT assessment_narrative_section_assessment_id_risk_category_id_key UNIQUE (assessment_id, risk_category_id);


--
-- Name: assessment_narrative_section assessment_narrative_section_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment_narrative_section
    ADD CONSTRAINT assessment_narrative_section_pkey PRIMARY KEY (id);


--
-- Name: assessment assessment_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment
    ADD CONSTRAINT assessment_pkey PRIMARY KEY (id);


--
-- Name: assessment_policy_reliance assessment_policy_reliance_assessment_id_risk_category_id_polic; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment_policy_reliance
    ADD CONSTRAINT assessment_policy_reliance_assessment_id_risk_category_id_polic UNIQUE NULLS NOT DISTINCT (assessment_id, risk_category_id, policy_chunk_id);


--
-- Name: assessment_policy_reliance assessment_policy_reliance_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment_policy_reliance
    ADD CONSTRAINT assessment_policy_reliance_pkey PRIMARY KEY (id);


--
-- Name: assessment_risk_score assessment_risk_score_assessment_id_risk_category_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment_risk_score
    ADD CONSTRAINT assessment_risk_score_assessment_id_risk_category_id_key UNIQUE (assessment_id, risk_category_id);


--
-- Name: assessment_risk_score assessment_risk_score_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment_risk_score
    ADD CONSTRAINT assessment_risk_score_pkey PRIMARY KEY (id);


--
-- Name: audit_event audit_event_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_event
    ADD CONSTRAINT audit_event_pkey PRIMARY KEY (id);


--
-- Name: change_request_attachment change_request_attachment_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.change_request_attachment
    ADD CONSTRAINT change_request_attachment_pkey PRIMARY KEY (id);


--
-- Name: change_request_clarification change_request_clarification_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.change_request_clarification
    ADD CONSTRAINT change_request_clarification_pkey PRIMARY KEY (id);


--
-- Name: change_request_external_snapshot change_request_external_snapshot_change_request_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.change_request_external_snapshot
    ADD CONSTRAINT change_request_external_snapshot_change_request_id_key UNIQUE (change_request_id);


--
-- Name: change_request_external_snapshot change_request_external_snapshot_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.change_request_external_snapshot
    ADD CONSTRAINT change_request_external_snapshot_pkey PRIMARY KEY (id);


--
-- Name: change_request change_request_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.change_request
    ADD CONSTRAINT change_request_pkey PRIMARY KEY (id);


--
-- Name: change_request change_request_request_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.change_request
    ADD CONSTRAINT change_request_request_number_key UNIQUE (request_number);


--
-- Name: change_request_sla change_request_sla_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.change_request_sla
    ADD CONSTRAINT change_request_sla_pkey PRIMARY KEY (change_request_id);


--
-- Name: change_request_stage_history change_request_stage_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.change_request_stage_history
    ADD CONSTRAINT change_request_stage_history_pkey PRIMARY KEY (id);


--
-- Name: change_request_type_category_map change_request_type_category_m_change_type_risk_category_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.change_request_type_category_map
    ADD CONSTRAINT change_request_type_category_m_change_type_risk_category_id_key UNIQUE (change_type, risk_category_id);


--
-- Name: change_request_type_category_map change_request_type_category_map_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.change_request_type_category_map
    ADD CONSTRAINT change_request_type_category_map_pkey PRIMARY KEY (id);


--
-- Name: committee_decision committee_decision_assessment_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.committee_decision
    ADD CONSTRAINT committee_decision_assessment_id_key UNIQUE (assessment_id);


--
-- Name: committee_decision committee_decision_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.committee_decision
    ADD CONSTRAINT committee_decision_pkey PRIMARY KEY (id);


--
-- Name: committee_vote committee_vote_assessment_id_committee_member_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.committee_vote
    ADD CONSTRAINT committee_vote_assessment_id_committee_member_user_id_key UNIQUE (assessment_id, committee_member_user_id);


--
-- Name: committee_vote committee_vote_conditions_required; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.committee_vote
    ADD CONSTRAINT committee_vote_conditions_required CHECK (((vote <> 'ApproveWithConditions'::text) OR ((conditions_text IS NOT NULL) AND (length(TRIM(BOTH FROM conditions_text)) > 0)))) NOT VALID;


--
-- Name: committee_vote committee_vote_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.committee_vote
    ADD CONSTRAINT committee_vote_pkey PRIMARY KEY (id);


--
-- Name: committee_vote committee_vote_rationale_required; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.committee_vote
    ADD CONSTRAINT committee_vote_rationale_required CHECK (((vote <> ALL (ARRAY['Reject'::text, 'Defer'::text])) OR ((rationale IS NOT NULL) AND (length(TRIM(BOTH FROM rationale)) > 0)))) NOT VALID;


--
-- Name: control control_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.control
    ADD CONSTRAINT control_pkey PRIMARY KEY (id);


--
-- Name: control control_risk_category_id_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.control
    ADD CONSTRAINT control_risk_category_id_name_key UNIQUE (risk_category_id, name);


--
-- Name: extracted_field extracted_field_change_request_id_field_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.extracted_field
    ADD CONSTRAINT extracted_field_change_request_id_field_key_key UNIQUE (change_request_id, field_key);


--
-- Name: extracted_field extracted_field_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.extracted_field
    ADD CONSTRAINT extracted_field_pkey PRIMARY KEY (id);


--
-- Name: policy_chunk policy_chunk_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.policy_chunk
    ADD CONSTRAINT policy_chunk_pkey PRIMARY KEY (id);


--
-- Name: policy_chunk policy_chunk_policy_document_id_section_ref_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.policy_chunk
    ADD CONSTRAINT policy_chunk_policy_document_id_section_ref_key UNIQUE (policy_document_id, section_ref);


--
-- Name: policy_document policy_document_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.policy_document
    ADD CONSTRAINT policy_document_pkey PRIMARY KEY (id);


--
-- Name: risk_category risk_category_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.risk_category
    ADD CONSTRAINT risk_category_pkey PRIMARY KEY (id);


--
-- Name: risk_category risk_category_risk_framework_id_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.risk_category
    ADD CONSTRAINT risk_category_risk_framework_id_code_key UNIQUE (risk_framework_id, code);


--
-- Name: risk_framework risk_framework_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.risk_framework
    ADD CONSTRAINT risk_framework_name_key UNIQUE (name);


--
-- Name: risk_framework risk_framework_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.risk_framework
    ADD CONSTRAINT risk_framework_pkey PRIMARY KEY (id);


--
-- Name: risk_subfactor risk_subfactor_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.risk_subfactor
    ADD CONSTRAINT risk_subfactor_pkey PRIMARY KEY (id);


--
-- Name: risk_subfactor risk_subfactor_risk_category_id_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.risk_subfactor
    ADD CONSTRAINT risk_subfactor_risk_category_id_name_key UNIQUE (risk_category_id, name);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (filename);


--
-- Name: scoring_config scoring_config_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scoring_config
    ADD CONSTRAINT scoring_config_pkey PRIMARY KEY (id);


--
-- Name: sla_config sla_config_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sla_config
    ADD CONSTRAINT sla_config_pkey PRIMARY KEY (id);


--
-- Name: sla_config sla_config_version_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sla_config
    ADD CONSTRAINT sla_config_version_number_key UNIQUE (version_number);


--
-- Name: sla_holiday sla_holiday_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sla_holiday
    ADD CONSTRAINT sla_holiday_pkey PRIMARY KEY (id);


--
-- Name: sla_target sla_target_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sla_target
    ADD CONSTRAINT sla_target_pkey PRIMARY KEY (sla_config_id, change_type, stage);


--
-- Name: workflow_rule workflow_rule_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_rule
    ADD CONSTRAINT workflow_rule_pkey PRIMARY KEY (id);


--
-- Name: idx_audit_event_assessment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_event_assessment ON public.audit_event USING btree (assessment_id, created_at);


--
-- Name: idx_audit_event_change_request; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_event_change_request ON public.audit_event USING btree (change_request_id, created_at);


--
-- Name: idx_policy_chunk_search_vector; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_policy_chunk_search_vector ON public.policy_chunk USING gin (search_vector);


--
-- Name: idx_stage_history_request; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_stage_history_request ON public.change_request_stage_history USING btree (change_request_id, entered_at);


--
-- Name: ux_sla_config_single_active; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_sla_config_single_active ON public.sla_config USING btree (is_active) WHERE is_active;


--
-- Name: ux_sla_holiday_active_date; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_sla_holiday_active_date ON public.sla_holiday USING btree (holiday_date) WHERE is_active;


--
-- Name: ux_stage_history_one_open; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_stage_history_one_open ON public.change_request_stage_history USING btree (change_request_id) WHERE (left_at IS NULL);


--
-- Name: audit_event trg_block_audit_event_mutation; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_block_audit_event_mutation BEFORE DELETE OR UPDATE ON public.audit_event FOR EACH ROW EXECUTE FUNCTION public.fn_block_audit_event_mutation();


--
-- Name: change_request trg_sla_request_submitted; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_sla_request_submitted AFTER INSERT ON public.change_request FOR EACH ROW EXECUTE FUNCTION public.fn_trg_sla_request_submitted();


--
-- Name: change_request trg_sla_status_changed; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_sla_status_changed AFTER UPDATE OF status ON public.change_request FOR EACH ROW WHEN ((old.status IS DISTINCT FROM new.status)) EXECUTE FUNCTION public.fn_trg_sla_status_changed();


--
-- Name: app_user_role app_user_role_granted_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_user_role
    ADD CONSTRAINT app_user_role_granted_by_user_id_fkey FOREIGN KEY (granted_by_user_id) REFERENCES public.app_user(id);


--
-- Name: app_user_role app_user_role_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_user_role
    ADD CONSTRAINT app_user_role_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.app_user(id);


--
-- Name: assessment_category_mapping assessment_category_mapping_assessment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment_category_mapping
    ADD CONSTRAINT assessment_category_mapping_assessment_id_fkey FOREIGN KEY (assessment_id) REFERENCES public.assessment(id);


--
-- Name: assessment_category_mapping assessment_category_mapping_created_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment_category_mapping
    ADD CONSTRAINT assessment_category_mapping_created_by_user_id_fkey FOREIGN KEY (created_by_user_id) REFERENCES public.app_user(id);


--
-- Name: assessment_category_mapping assessment_category_mapping_risk_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment_category_mapping
    ADD CONSTRAINT assessment_category_mapping_risk_category_id_fkey FOREIGN KEY (risk_category_id) REFERENCES public.risk_category(id);


--
-- Name: assessment assessment_change_request_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment
    ADD CONSTRAINT assessment_change_request_id_fkey FOREIGN KEY (change_request_id) REFERENCES public.change_request(id);


--
-- Name: assessment assessment_finalized_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment
    ADD CONSTRAINT assessment_finalized_by_user_id_fkey FOREIGN KEY (finalized_by_user_id) REFERENCES public.app_user(id);


--
-- Name: assessment_narrative_section assessment_narrative_section_assessment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment_narrative_section
    ADD CONSTRAINT assessment_narrative_section_assessment_id_fkey FOREIGN KEY (assessment_id) REFERENCES public.assessment(id);


--
-- Name: assessment_narrative_section assessment_narrative_section_risk_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment_narrative_section
    ADD CONSTRAINT assessment_narrative_section_risk_category_id_fkey FOREIGN KEY (risk_category_id) REFERENCES public.risk_category(id);


--
-- Name: assessment_narrative_section assessment_narrative_section_updated_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment_narrative_section
    ADD CONSTRAINT assessment_narrative_section_updated_by_user_id_fkey FOREIGN KEY (updated_by_user_id) REFERENCES public.app_user(id);


--
-- Name: assessment_policy_reliance assessment_policy_reliance_assessment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment_policy_reliance
    ADD CONSTRAINT assessment_policy_reliance_assessment_id_fkey FOREIGN KEY (assessment_id) REFERENCES public.assessment(id);


--
-- Name: assessment_policy_reliance assessment_policy_reliance_decided_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment_policy_reliance
    ADD CONSTRAINT assessment_policy_reliance_decided_by_user_id_fkey FOREIGN KEY (decided_by_user_id) REFERENCES public.app_user(id);


--
-- Name: assessment_policy_reliance assessment_policy_reliance_policy_chunk_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment_policy_reliance
    ADD CONSTRAINT assessment_policy_reliance_policy_chunk_id_fkey FOREIGN KEY (policy_chunk_id) REFERENCES public.policy_chunk(id);


--
-- Name: assessment_policy_reliance assessment_policy_reliance_risk_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment_policy_reliance
    ADD CONSTRAINT assessment_policy_reliance_risk_category_id_fkey FOREIGN KEY (risk_category_id) REFERENCES public.risk_category(id);


--
-- Name: assessment_risk_score assessment_risk_score_assessment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment_risk_score
    ADD CONSTRAINT assessment_risk_score_assessment_id_fkey FOREIGN KEY (assessment_id) REFERENCES public.assessment(id);


--
-- Name: assessment_risk_score assessment_risk_score_created_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment_risk_score
    ADD CONSTRAINT assessment_risk_score_created_by_user_id_fkey FOREIGN KEY (created_by_user_id) REFERENCES public.app_user(id);


--
-- Name: assessment_risk_score assessment_risk_score_risk_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment_risk_score
    ADD CONSTRAINT assessment_risk_score_risk_category_id_fkey FOREIGN KEY (risk_category_id) REFERENCES public.risk_category(id);


--
-- Name: audit_event audit_event_actor_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_event
    ADD CONSTRAINT audit_event_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES public.app_user(id);


--
-- Name: audit_event audit_event_assessment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_event
    ADD CONSTRAINT audit_event_assessment_id_fkey FOREIGN KEY (assessment_id) REFERENCES public.assessment(id);


--
-- Name: audit_event audit_event_change_request_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_event
    ADD CONSTRAINT audit_event_change_request_id_fkey FOREIGN KEY (change_request_id) REFERENCES public.change_request(id);


--
-- Name: change_request_attachment change_request_attachment_change_request_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.change_request_attachment
    ADD CONSTRAINT change_request_attachment_change_request_id_fkey FOREIGN KEY (change_request_id) REFERENCES public.change_request(id);


--
-- Name: change_request_attachment change_request_attachment_superseded_by_attachment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.change_request_attachment
    ADD CONSTRAINT change_request_attachment_superseded_by_attachment_id_fkey FOREIGN KEY (superseded_by_attachment_id) REFERENCES public.change_request_attachment(id);


--
-- Name: change_request_attachment change_request_attachment_uploaded_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.change_request_attachment
    ADD CONSTRAINT change_request_attachment_uploaded_by_user_id_fkey FOREIGN KEY (uploaded_by_user_id) REFERENCES public.app_user(id);


--
-- Name: change_request_clarification change_request_clarification_change_request_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.change_request_clarification
    ADD CONSTRAINT change_request_clarification_change_request_id_fkey FOREIGN KEY (change_request_id) REFERENCES public.change_request(id);


--
-- Name: change_request_clarification change_request_clarification_requested_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.change_request_clarification
    ADD CONSTRAINT change_request_clarification_requested_by_user_id_fkey FOREIGN KEY (requested_by_user_id) REFERENCES public.app_user(id);


--
-- Name: change_request_external_snapshot change_request_external_snapshot_change_request_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.change_request_external_snapshot
    ADD CONSTRAINT change_request_external_snapshot_change_request_id_fkey FOREIGN KEY (change_request_id) REFERENCES public.change_request(id);


--
-- Name: change_request_sla change_request_sla_change_request_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.change_request_sla
    ADD CONSTRAINT change_request_sla_change_request_id_fkey FOREIGN KEY (change_request_id) REFERENCES public.change_request(id);


--
-- Name: change_request_sla change_request_sla_sla_config_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.change_request_sla
    ADD CONSTRAINT change_request_sla_sla_config_id_fkey FOREIGN KEY (sla_config_id) REFERENCES public.sla_config(id);


--
-- Name: change_request_stage_history change_request_stage_history_change_request_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.change_request_stage_history
    ADD CONSTRAINT change_request_stage_history_change_request_id_fkey FOREIGN KEY (change_request_id) REFERENCES public.change_request(id);


--
-- Name: change_request change_request_submitted_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.change_request
    ADD CONSTRAINT change_request_submitted_by_user_id_fkey FOREIGN KEY (submitted_by_user_id) REFERENCES public.app_user(id);


--
-- Name: change_request_type_category_map change_request_type_category_map_risk_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.change_request_type_category_map
    ADD CONSTRAINT change_request_type_category_map_risk_category_id_fkey FOREIGN KEY (risk_category_id) REFERENCES public.risk_category(id);


--
-- Name: committee_decision committee_decision_assessment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.committee_decision
    ADD CONSTRAINT committee_decision_assessment_id_fkey FOREIGN KEY (assessment_id) REFERENCES public.assessment(id);


--
-- Name: committee_vote committee_vote_assessment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.committee_vote
    ADD CONSTRAINT committee_vote_assessment_id_fkey FOREIGN KEY (assessment_id) REFERENCES public.assessment(id);


--
-- Name: committee_vote committee_vote_committee_member_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.committee_vote
    ADD CONSTRAINT committee_vote_committee_member_user_id_fkey FOREIGN KEY (committee_member_user_id) REFERENCES public.app_user(id);


--
-- Name: control control_risk_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.control
    ADD CONSTRAINT control_risk_category_id_fkey FOREIGN KEY (risk_category_id) REFERENCES public.risk_category(id);


--
-- Name: extracted_field extracted_field_attachment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.extracted_field
    ADD CONSTRAINT extracted_field_attachment_id_fkey FOREIGN KEY (attachment_id) REFERENCES public.change_request_attachment(id);


--
-- Name: extracted_field extracted_field_change_request_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.extracted_field
    ADD CONSTRAINT extracted_field_change_request_id_fkey FOREIGN KEY (change_request_id) REFERENCES public.change_request(id);


--
-- Name: extracted_field extracted_field_updated_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.extracted_field
    ADD CONSTRAINT extracted_field_updated_by_user_id_fkey FOREIGN KEY (updated_by_user_id) REFERENCES public.app_user(id);


--
-- Name: policy_chunk policy_chunk_policy_document_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.policy_chunk
    ADD CONSTRAINT policy_chunk_policy_document_id_fkey FOREIGN KEY (policy_document_id) REFERENCES public.policy_document(id);


--
-- Name: policy_chunk policy_chunk_risk_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.policy_chunk
    ADD CONSTRAINT policy_chunk_risk_category_id_fkey FOREIGN KEY (risk_category_id) REFERENCES public.risk_category(id);


--
-- Name: policy_document policy_document_risk_framework_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.policy_document
    ADD CONSTRAINT policy_document_risk_framework_id_fkey FOREIGN KEY (risk_framework_id) REFERENCES public.risk_framework(id);


--
-- Name: risk_category risk_category_risk_framework_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.risk_category
    ADD CONSTRAINT risk_category_risk_framework_id_fkey FOREIGN KEY (risk_framework_id) REFERENCES public.risk_framework(id);


--
-- Name: risk_subfactor risk_subfactor_risk_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.risk_subfactor
    ADD CONSTRAINT risk_subfactor_risk_category_id_fkey FOREIGN KEY (risk_category_id) REFERENCES public.risk_category(id);


--
-- Name: scoring_config scoring_config_created_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scoring_config
    ADD CONSTRAINT scoring_config_created_by_user_id_fkey FOREIGN KEY (created_by_user_id) REFERENCES public.app_user(id);


--
-- Name: scoring_config scoring_config_risk_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scoring_config
    ADD CONSTRAINT scoring_config_risk_category_id_fkey FOREIGN KEY (risk_category_id) REFERENCES public.risk_category(id);


--
-- Name: sla_config sla_config_created_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sla_config
    ADD CONSTRAINT sla_config_created_by_user_id_fkey FOREIGN KEY (created_by_user_id) REFERENCES public.app_user(id);


--
-- Name: sla_holiday sla_holiday_created_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sla_holiday
    ADD CONSTRAINT sla_holiday_created_by_user_id_fkey FOREIGN KEY (created_by_user_id) REFERENCES public.app_user(id);


--
-- Name: sla_target sla_target_sla_config_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sla_target
    ADD CONSTRAINT sla_target_sla_config_id_fkey FOREIGN KEY (sla_config_id) REFERENCES public.sla_config(id);


--
-- Name: workflow_rule workflow_rule_created_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_rule
    ADD CONSTRAINT workflow_rule_created_by_user_id_fkey FOREIGN KEY (created_by_user_id) REFERENCES public.app_user(id);


--
-- PostgreSQL database dump complete
--

\unrestrict xeS8sDMl5gIZ5eGmceey9gNe58JwrrSUn3oSKu7Xe23RcfklTqVYzJwxs0WuTLM

