-- Epic 19: the due date - p_start advanced by p_days business days, keeping p_start's time of day.
-- Counting starts the day after p_start, so entering a stage on a Saturday with a 2-day target is due
-- on Tuesday. p_days <= 0 returns p_start unchanged.
CREATE OR REPLACE FUNCTION fn_sla_add_business_days(p_start TIMESTAMPTZ, p_days INT)
RETURNS TIMESTAMPTZ AS $$
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
$$ LANGUAGE plpgsql STABLE;
