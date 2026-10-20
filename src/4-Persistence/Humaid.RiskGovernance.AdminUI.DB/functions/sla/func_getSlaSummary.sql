-- Epic 19 / US-19.5 AC1: how many open requests are in each SLA state, for the counts above the SLA
-- grid. Respects the grid's stage / type / search filters but deliberately NOT its state filter, so the
-- counts stay put while the user picks a state. A null overall_state is a request with no target set.
CREATE OR REPLACE FUNCTION func_getSlaSummary(
    p_stage TEXT DEFAULT NULL,
    p_change_type TEXT DEFAULT NULL,
    p_search TEXT DEFAULT NULL
)
RETURNS TABLE (overall_state TEXT, request_count INT) AS $$
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
$$ LANGUAGE plpgsql STABLE;
