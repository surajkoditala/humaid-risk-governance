-- Epic 19: whole business days elapsed after p_start's calendar day, up to and including p_end's
-- calendar day. Same-day = 0. Never negative.
-- (plpgsql rather than sql: functions/ files apply in alphabetical order, and a plpgsql body is only
-- resolved at call time, so this doesn't depend on fn_sla_is_business_day being created first.)
CREATE OR REPLACE FUNCTION fn_sla_business_days_between(p_start TIMESTAMPTZ, p_end TIMESTAMPTZ)
RETURNS INT AS $$
BEGIN
    RETURN (
        SELECT COUNT(*)::INT
        FROM generate_series(
            ((p_start AT TIME ZONE 'UTC')::date + 1)::timestamp,
            (p_end AT TIME ZONE 'UTC')::date::timestamp,
            interval '1 day') AS g(d)
        WHERE fn_sla_is_business_day(g.d::date));
END;
$$ LANGUAGE plpgsql STABLE;
