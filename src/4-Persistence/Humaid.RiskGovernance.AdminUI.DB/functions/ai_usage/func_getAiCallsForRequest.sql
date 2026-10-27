-- Measured token use: every AI call recorded against one change request, oldest first - rows
-- written with the request id directly, plus rows that only carried the request's assessment id.
CREATE OR REPLACE FUNCTION func_getAiCallsForRequest(p_change_request_id UUID)
RETURNS TABLE (
    id UUID, change_request_id UUID, assessment_id UUID, operation TEXT, provider TEXT, model TEXT,
    input_tokens BIGINT, output_tokens BIGINT, cache_read_tokens BIGINT, cache_creation_tokens BIGINT,
    duration_ms INT, created_at TIMESTAMPTZ
) AS $$
    SELECT l.id, l.change_request_id, l.assessment_id, l.operation, l.provider, l.model,
           l.input_tokens, l.output_tokens, l.cache_read_tokens, l.cache_creation_tokens,
           l.duration_ms, l.created_at
    FROM ai_call_log l
    WHERE l.change_request_id = p_change_request_id
       OR l.assessment_id IN (SELECT a.id FROM assessment a WHERE a.change_request_id = p_change_request_id)
    ORDER BY l.created_at ASC;
$$ LANGUAGE sql STABLE;
