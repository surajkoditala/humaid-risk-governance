-- Epic 19: a business day is Monday-Friday and not on the active sla_holiday calendar (US-19.1 AC6).
-- Dates are read in UTC, so a given timestamp always maps to the same calendar day regardless of the
-- session time zone - SLA arithmetic must be reproducible by an examiner (US-19.5 AC5).
CREATE OR REPLACE FUNCTION fn_sla_is_business_day(p_date DATE)
RETURNS BOOLEAN AS $$
    SELECT EXTRACT(ISODOW FROM p_date) < 6
       AND NOT EXISTS (SELECT 1 FROM sla_holiday h WHERE h.is_active AND h.holiday_date = p_date);
$$ LANGUAGE sql STABLE;
