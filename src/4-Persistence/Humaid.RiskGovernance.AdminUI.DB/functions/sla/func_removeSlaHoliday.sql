-- Epic 19 / US-19.1 AC6: take a date off the holiday calendar. The row is deactivated, never deleted,
-- so the calendar's history stays reconstructable. Audited with the reason.
CREATE OR REPLACE FUNCTION func_removeSlaHoliday(
    p_holiday_id UUID,
    p_reason TEXT,
    p_actor_user_id UUID
) RETURNS VOID AS $$
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
$$ LANGUAGE plpgsql;
