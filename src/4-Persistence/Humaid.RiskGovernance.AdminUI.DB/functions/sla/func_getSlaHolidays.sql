-- Epic 19 / US-19.1 AC6: the active holiday calendar business-day arithmetic excludes.
CREATE OR REPLACE FUNCTION func_getSlaHolidays()
RETURNS TABLE (id UUID, holiday_date DATE, reason TEXT, created_at TIMESTAMPTZ) AS $$
BEGIN
    RETURN QUERY
    SELECT h.id, h.holiday_date, h.reason, h.created_at
    FROM sla_holiday h
    WHERE h.is_active
    ORDER BY h.holiday_date;
END;
$$ LANGUAGE plpgsql STABLE;
