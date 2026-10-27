-- Measured token use: appends one ai_call_log row for a successful AI call. Called by the AI
-- provider clients with whatever request context the calling service established; either id may be
-- NULL. When only the assessment is known, the change request is derived from it, so a row for the
-- narrative step (which knows the assessment, not the request) still lands on the right request.
-- A token count the provider did not report stays NULL - it is never defaulted to 0.
CREATE OR REPLACE FUNCTION func_logAiCall(
    p_change_request_id UUID, p_assessment_id UUID, p_operation TEXT, p_provider TEXT, p_model TEXT,
    p_input_tokens BIGINT, p_output_tokens BIGINT, p_cache_read_tokens BIGINT, p_cache_creation_tokens BIGINT,
    p_duration_ms INT
) RETURNS UUID AS $$
DECLARE
    v_change_request_id UUID := p_change_request_id;
    v_id UUID;
BEGIN
    IF v_change_request_id IS NULL AND p_assessment_id IS NOT NULL THEN
        SELECT a.change_request_id INTO v_change_request_id FROM assessment a WHERE a.id = p_assessment_id;
    END IF;

    INSERT INTO ai_call_log (
        change_request_id, assessment_id, operation, provider, model,
        input_tokens, output_tokens, cache_read_tokens, cache_creation_tokens, duration_ms)
    VALUES (
        v_change_request_id, p_assessment_id, p_operation, p_provider, p_model,
        p_input_tokens, p_output_tokens, p_cache_read_tokens, p_cache_creation_tokens, p_duration_ms)
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;
