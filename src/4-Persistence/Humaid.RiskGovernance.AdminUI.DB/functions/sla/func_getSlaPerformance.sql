-- Epic 19 / US-19.5 AC2-AC3: cycle time of requests that have finished a stage / been decided -
-- median and 90th percentile in business days, the target, and the share that met their SLA - per
-- change type and stage, plus an all-types end-to-end row (change_type 'All') so the headline figure
-- can be set against the 15-20 business-day baseline. Derived only from the frozen stage_history /
-- change_request_sla values, so every figure can be reproduced from recorded timestamps.
CREATE OR REPLACE FUNCTION func_getSlaPerformance(p_change_type TEXT DEFAULT NULL)
RETURNS TABLE (
    change_type TEXT, stage TEXT, sample_count INT, target_days INT,
    median_days NUMERIC, p90_days NUMERIC, met_percent NUMERIC
) AS $$
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
$$ LANGUAGE plpgsql STABLE;
