-- Measured token use per change request: brings databases deployed BEFORE this change up to date.
-- A brand-new database gets the same objects from schema/016_ai_call_log.sql via deploy_all.sql, so
-- this file is recorded as already-applied there. Identical DDL by design (every statement is IF NOT
-- EXISTS / DROP IF EXISTS, so it is safe either way). The functions that write and read the table are
-- in functions/ai_usage/ and are re-applied on every startup.

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
