-- Epic 19 / US-19.1 AC6: add a date to the holiday calendar. Business-day calculations use it from
-- this point on (open requests' due dates shift; finished stages keep their frozen results). Audited.
CREATE OR REPLACE FUNCTION func_addSlaHoliday(
    p_holiday_date DATE,
    p_reason TEXT,
    p_actor_user_id UUID
) RETURNS UUID AS $$
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
$$ LANGUAGE plpgsql;
