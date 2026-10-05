-- Epic 19 / US-19.2 AC4: business days within (p_from, p_to] on which the Product Owner was being
-- waited on - i.e. an Open clarification existed (created before that day, not yet answered by the end
-- of it). Counted per calendar day, so overlapping clarifications are never double-counted.
-- (plpgsql for the same alphabetical-apply-order reason as fn_slaBusinessDaysBetween.sql.)
CREATE OR REPLACE FUNCTION fn_sla_waiting_days(p_change_request_id UUID, p_from TIMESTAMPTZ, p_to TIMESTAMPTZ)
RETURNS INT AS $$
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
$$ LANGUAGE plpgsql STABLE;
