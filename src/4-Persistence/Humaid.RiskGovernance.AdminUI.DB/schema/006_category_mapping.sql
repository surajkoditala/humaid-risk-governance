-- Epic 2 — current-state table. History (the original AI proposal vs. the analyst's final
-- selection, with reason) lives in audit_event, not in extra version columns here - see
-- docs/architecture/architecture-mapping.md "Audit design".

CREATE TABLE assessment_category_mapping (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assessment_id UUID NOT NULL REFERENCES assessment(id),
    risk_category_id UUID NOT NULL REFERENCES risk_category(id),
    source TEXT NOT NULL CHECK (source IN ('AiProposed','AnalystAdded')),
    ai_citation TEXT, -- the framework section the AI proposal cited; null when source = AnalystAdded
    is_active BOOLEAN NOT NULL DEFAULT true, -- false = analyst removed it; the row (and its audit trail) is kept, never deleted
    created_by_user_id UUID REFERENCES app_user(id), -- null when source = AiProposed (actor is 'system/AI')
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (assessment_id, risk_category_id)
);
