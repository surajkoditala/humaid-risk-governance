-- Measured token use, per change request. One append-only row per successful call the Workbench
-- makes to its AI provider: exactly the token counts the provider reported (and bills on), tagged
-- with the Workbench step that made the call. The same figures also go out as an OpenTelemetry
-- metric for fleet-wide monitoring; this table is what answers "what did THIS request cost".
--
-- Append-only at the data layer like audit_event (no update or delete function exists, and the
-- trigger below blocks them from any other client): a recorded cost must not be editable.
-- A token column is NULL when the provider did not report it - never 0 - so a missing figure
-- cannot be read as a free call. Informational only: nothing here gates, scores or decides.
--
-- Identical DDL to migrations/0011_ai_call_log.sql by design (every statement is IF NOT EXISTS /
-- DROP IF EXISTS, so it is safe either way).

CREATE TABLE IF NOT EXISTS ai_call_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    change_request_id UUID REFERENCES change_request(id),
    assessment_id UUID REFERENCES assessment(id),
    operation TEXT NOT NULL,   -- the Workbench step: 'category_mapping', 'document_extraction', 'narrative_drafting'
    provider TEXT NOT NULL,    -- 'anthropic' or 'az.ai.inference'
    model TEXT,                -- the model the provider reports having used
    input_tokens BIGINT CHECK (input_tokens >= 0),
    output_tokens BIGINT CHECK (output_tokens >= 0),
    cache_read_tokens BIGINT CHECK (cache_read_tokens >= 0),
    cache_creation_tokens BIGINT CHECK (cache_creation_tokens >= 0),
    duration_ms INT CHECK (duration_ms >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ai_call_log_change_request ON ai_call_log (change_request_id, created_at);
CREATE INDEX IF NOT EXISTS idx_ai_call_log_assessment ON ai_call_log (assessment_id, created_at);

CREATE OR REPLACE FUNCTION fn_block_ai_call_log_mutation() RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'ai_call_log is append-only: % is not permitted', TG_OP;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_block_ai_call_log_mutation ON ai_call_log;
CREATE TRIGGER trg_block_ai_call_log_mutation
    BEFORE UPDATE OR DELETE ON ai_call_log
    FOR EACH ROW EXECUTE FUNCTION fn_block_ai_call_log_mutation();
