-- Epic 19 / US-19.2 AC2: OnTrack, AtRisk (charged elapsed days have reached the warning threshold,
-- a percentage of the target) or Breached (past the due date). Null when no target is configured.
CREATE OR REPLACE FUNCTION fn_sla_state(p_now TIMESTAMPTZ, p_due TIMESTAMPTZ, p_elapsed INT, p_target INT, p_threshold_pct INT)
RETURNS TEXT AS $$
    SELECT CASE
        WHEN p_target IS NULL OR p_due IS NULL THEN NULL
        WHEN p_now > p_due THEN 'Breached'
        WHEN p_elapsed * 100 >= p_target * p_threshold_pct THEN 'AtRisk'
        ELSE 'OnTrack'
    END;
$$ LANGUAGE sql IMMUTABLE;
