-- Epic 3 — Policy corpus for retrieval, and the analyst's reliance decisions against it.
-- Retrieval (func_searchPolicyChunks) is deterministic Postgres full-text search on
-- search_vector - deliberately not an LLM/embedding call; see
-- docs/governance/human-in-the-loop-gates.md for the rationale.

CREATE TABLE policy_document (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    risk_framework_id UUID REFERENCES risk_framework(id),
    title TEXT NOT NULL,
    source_url TEXT NOT NULL,
    effective_date DATE,
    version_label TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE policy_chunk (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    policy_document_id UUID NOT NULL REFERENCES policy_document(id),
    risk_category_id UUID REFERENCES risk_category(id), -- the category this excerpt is most relevant to, when known
    section_ref TEXT NOT NULL,
    chunk_text TEXT NOT NULL,
    search_vector TSVECTOR GENERATED ALWAYS AS (to_tsvector('english', chunk_text)) STORED,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- Found duplicated 2-3x over in the deployed dev DB (DEF-032 investigation) - seed_policy_corpus.sql
    -- had no conflict target, so re-running it (harmless for every other seed file) silently
    -- cluttered search results with identical passages instead of adding coverage.
    UNIQUE (policy_document_id, section_ref)
);
CREATE INDEX idx_policy_chunk_search_vector ON policy_chunk USING GIN (search_vector);

CREATE TABLE assessment_policy_reliance (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assessment_id UUID NOT NULL REFERENCES assessment(id),
    risk_category_id UUID REFERENCES risk_category(id),
    policy_chunk_id UUID NOT NULL REFERENCES policy_chunk(id),
    decision TEXT NOT NULL CHECK (decision IN ('ReliedUpon','NotRelevant')),
    decided_by_user_id UUID NOT NULL REFERENCES app_user(id),
    decided_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- DEF-011: the same passage can legitimately be relied upon under more than one mapped
    -- category - risk_category_id must be part of the key or the second category's decision
    -- overwrites the first's (func_recordPolicyReliance.sql's ON CONFLICT target matches this).
    UNIQUE (assessment_id, risk_category_id, policy_chunk_id)
);
