-- Epic 9 — the immutable audit trail. Append-only AT THE DATA LAYER (US-9.2): no
-- func_updateAuditEvent / func_deleteAuditEvent is ever defined anywhere in functions/, and this
-- trigger makes bypassing that impossible even from a direct SQL client or a future admin tool -
-- not merely an application-level permission choice.

CREATE TABLE audit_event (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    change_request_id UUID REFERENCES change_request(id),
    assessment_id UUID REFERENCES assessment(id),
    entity_type TEXT NOT NULL, -- e.g. 'ChangeRequest','CategoryMapping','ExtractedField','NarrativeSection','RiskScore','ScoringConfig','WorkflowRule','CommitteeVote'
    entity_id UUID,
    action TEXT NOT NULL,      -- e.g. 'Created','AiProposed','AiExtracted','AiDrafted','Overridden','Corrected','Finalized','ConfigChanged'
    actor_user_id UUID REFERENCES app_user(id), -- null when actor_label = 'system/AI'
    actor_label TEXT NOT NULL DEFAULT 'system/AI', -- 'human' or 'system/AI'
    before_value JSONB,
    after_value JSONB,
    reason TEXT, -- mandatory for any human edit/override - enforced in the writing function, not here
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_audit_event_change_request ON audit_event (change_request_id, created_at);
CREATE INDEX idx_audit_event_assessment ON audit_event (assessment_id, created_at);

CREATE OR REPLACE FUNCTION fn_block_audit_event_mutation() RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'audit_event is append-only: % is not permitted', TG_OP;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_block_audit_event_mutation
    BEFORE UPDATE OR DELETE ON audit_event
    FOR EACH ROW EXECUTE FUNCTION fn_block_audit_event_mutation();
