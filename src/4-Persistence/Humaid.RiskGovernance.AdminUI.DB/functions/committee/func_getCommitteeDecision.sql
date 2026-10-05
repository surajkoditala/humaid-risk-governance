-- US-8.3 AC3: conditions stay visibly attached to the request record for future reference, not
-- just buried in a vote comment.
CREATE OR REPLACE FUNCTION func_getCommitteeDecision(p_assessment_id UUID)
RETURNS TABLE (id UUID, resolution TEXT, conditions_text TEXT, decided_at TIMESTAMPTZ) AS $$
    SELECT d.id, d.resolution, d.conditions_text, d.decided_at
    FROM committee_decision d WHERE d.assessment_id = p_assessment_id;
$$ LANGUAGE sql STABLE;
