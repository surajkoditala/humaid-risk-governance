-- Opens (or returns the existing) assessment workspace for a change_request. Called the first
-- time an analyst enters the workspace for that request.
CREATE OR REPLACE FUNCTION func_getOrCreateAssessment(p_change_request_id UUID)
RETURNS UUID AS $$
DECLARE
    v_id UUID;
BEGIN
    SELECT id INTO v_id FROM assessment WHERE change_request_id = p_change_request_id;
    IF v_id IS NULL THEN
        v_id := gen_random_uuid();
        INSERT INTO assessment (id, change_request_id) VALUES (v_id, p_change_request_id);
        UPDATE change_request SET status = 'InAssessment' WHERE id = p_change_request_id AND status = 'Submitted';
    END IF;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;
