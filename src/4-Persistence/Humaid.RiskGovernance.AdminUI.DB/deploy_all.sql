-- ==================================================================================
-- deploy_all.sql - GENERATED FILE. Do not edit directly.
-- Regenerate with ./generate_deploy_all.sh after changing schema/, functions/, or seed/.
--
-- One-shot setup: creates every table, every stored function, and seeds synthetic dev
-- data, against an EMPTY database. Run once. Schema statements are plain CREATE TABLE
-- (not idempotent by design - see README.md), so re-running against a non-empty
-- database will fail on the first already-existing table. Drop and recreate the
-- database first if you need to re-run this.
--
-- Usage:
--   createdb -U postgres -h localhost -p 5433 risk_governance_db
--   psql -U postgres -h localhost -p 5433 -d risk_governance_db -v ON_ERROR_STOP=1 -f deploy_all.sql
-- ==================================================================================

BEGIN;

-- ============================== schema ==============================================

-- ---- schema/001_extensions_and_conventions.sql ----
-- Risk Assessment Workbench schema.
-- Apply in numeric order: schema/*.sql, then functions/**/*.sql, then seed/*.sql.
-- See ../README.md for the exact psql invocation.

-- gen_random_uuid() is a Postgres core builtin since PG13 - no extension needed (and Azure
-- Database for PostgreSQL Flexible Server doesn't allow-list pgcrypto by default, so trying to
-- CREATE EXTENSION it there fails outright). Deliberately no CREATE EXTENSION line here.

-- Conventions used throughout this schema:
--  * Every table has a UUID primary key (gen_random_uuid()).
--  * Enumerated columns are TEXT + CHECK, not native Postgres ENUM - adding an allowed value
--    later is an ALTER TABLE, not an ALTER TYPE against every dependent object/function.
--  * "Who did this" is always either an app_user id, or NULL with actor_label = 'system/AI' for
--    anything the platform itself produced (an AI call or a deterministic calculation).
--  * Nothing is ever hard-deleted or overwritten without a corresponding audit_event row - see
--    013_audit.sql and docs/architecture/architecture-mapping.md.

-- ---- schema/002_reference_data.sql ----
-- Epic 2 — Risk Categorization & Framework Mapping: the named, citable supervisory framework
-- (FFIEC BSA/AML Examination Manual, per CLAUDE.md's stated decision - hardcoded for the MVP, not
-- a multi-framework config table; see docs/architecture/architecture-mapping.md for the note on
-- the config-driven alternative as a documented extension point).

CREATE TABLE risk_framework (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    citation_source TEXT NOT NULL, -- e.g. 'FFIEC BSA/AML Examination Manual (bsaaml.ffiec.gov)'
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE risk_category (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    risk_framework_id UUID NOT NULL REFERENCES risk_framework(id),
    code TEXT NOT NULL,              -- e.g. 'PRODUCTS_SERVICES'
    name TEXT NOT NULL,              -- e.g. 'Products & Services'
    citation_section TEXT NOT NULL,  -- the specific framework section this category cites back to
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (risk_framework_id, code)
);

CREATE TABLE risk_subfactor (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    risk_category_id UUID NOT NULL REFERENCES risk_category(id),
    name TEXT NOT NULL, -- e.g. 'ACH', 'Wire transfers', 'Correspondent banking'
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (risk_category_id, name)
);

-- CLAUDE.md's own "change-request-type -> primary category mapping" table. Epic 2's AI proposal
-- is grounded against this (a lookup, not invented from scratch) before Claude adds citations.
CREATE TABLE change_request_type_category_map (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    change_type TEXT NOT NULL CHECK (change_type IN ('Product','Feature','Process','Vendor','Geography','CustomerSegment')),
    risk_category_id UUID NOT NULL REFERENCES risk_category(id),
    weight TEXT NOT NULL CHECK (weight IN ('Primary','Secondary')),
    UNIQUE (change_type, risk_category_id)
);

-- ---- schema/003_users.sql ----
-- Maps an Auth0 identity to the three in-app roles from CLAUDE.md (Product Owner, FCRM Analyst,
-- Risk Committee Member) plus Admin for platform configuration (Epic 10).

CREATE TABLE app_user (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    auth0_subject TEXT NOT NULL UNIQUE, -- Auth0 'sub' claim (synthetic 'seed|...' values for seeded dev users)
    email TEXT NOT NULL,
    display_name TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('ProductOwner','Analyst','CommitteeMember','Admin')),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---- schema/004_change_requests.sql ----
-- Epic 1 — Change Request Intake.

CREATE SEQUENCE change_request_number_seq START 1;

CREATE TABLE change_request (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    request_number TEXT NOT NULL UNIQUE, -- immutable, human-readable (e.g. 'CR-2026-00001'); assigned by func_createChangeRequest
    change_type TEXT NOT NULL CHECK (change_type IN ('Product','Feature','Process','Vendor','Geography','CustomerSegment')),
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    type_specific_fields JSONB NOT NULL DEFAULT '{}'::jsonb, -- e.g. vendor name/jurisdiction/data access scope; target country/region
    status TEXT NOT NULL DEFAULT 'Submitted' CHECK (status IN ('Submitted','InAssessment','PendingCommittee','Decisioned')),
    submitted_by_user_id UUID NOT NULL REFERENCES app_user(id),
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE change_request_attachment (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    change_request_id UUID NOT NULL REFERENCES change_request(id),
    file_name TEXT NOT NULL,
    content_type TEXT NOT NULL CHECK (content_type IN (
        'application/pdf',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    )),
    storage_path TEXT NOT NULL, -- opaque pointer to wherever the blob actually lives; this schema doesn't care
    extracted_text TEXT, -- MVP: plain-text content supplied at upload time for Epic 4 to run against - no PDF/DOCX
                          -- parser in this pass; see docs/architecture/architecture-mapping.md
    version_number INT NOT NULL DEFAULT 1,
    superseded_by_attachment_id UUID REFERENCES change_request_attachment(id), -- replacing a doc = new row + version (US-1.2), never an overwrite
    uploaded_by_user_id UUID NOT NULL REFERENCES app_user(id),
    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE change_request_clarification (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    change_request_id UUID NOT NULL REFERENCES change_request(id),
    requested_by_user_id UUID NOT NULL REFERENCES app_user(id),
    question TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'Open' CHECK (status IN ('Open','Answered')),
    answer TEXT,
    answered_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---- schema/005_assessments.sql ----
-- The FCRM analyst's working record for a change_request. Kept separate from change_request
-- itself: the request is "what was asked", the assessment is "how FCRM is deciding on it".

CREATE TABLE assessment (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    change_request_id UUID NOT NULL UNIQUE REFERENCES change_request(id),
    status TEXT NOT NULL DEFAULT 'Draft' CHECK (status IN ('Draft','Finalized')),
    scoring_config_version_id UUID, -- FK added in 010_scoring.sql, once scoring_config exists (avoids a forward reference here)
    finalized_by_user_id UUID REFERENCES app_user(id),
    finalized_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---- schema/006_category_mapping.sql ----
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

-- ---- schema/007_policy_corpus.sql ----
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
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
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
    UNIQUE (assessment_id, policy_chunk_id)
);

-- ---- schema/008_document_extraction.sql ----
-- Epic 4 — structured facts pulled from a change_request's attachments.

CREATE TABLE extracted_field (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    change_request_id UUID NOT NULL REFERENCES change_request(id),
    attachment_id UUID REFERENCES change_request_attachment(id),
    field_key TEXT NOT NULL, -- e.g. 'vendor_jurisdiction', 'data_flows', 'customer_types_affected'
    field_value TEXT,
    confidence NUMERIC(4,3), -- 0.000-1.000; null once source = AnalystCorrected (a human wrote it - "confidence" no longer applies)
    needs_review BOOLEAN NOT NULL DEFAULT false,
    source_excerpt TEXT, -- pointer/quote back to the exact source page/section
    source TEXT NOT NULL CHECK (source IN ('AiExtracted','AnalystCorrected')),
    updated_by_user_id UUID REFERENCES app_user(id),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (change_request_id, field_key)
);

-- ---- schema/009_narrative.sql ----
-- Epic 5 — one narrative section per mapped risk category, drafted independently so an analyst
-- can accept/edit/regenerate one category without touching the others (see user-stories.md
-- US-5.1's noted assumption).

CREATE TABLE assessment_narrative_section (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assessment_id UUID NOT NULL REFERENCES assessment(id),
    risk_category_id UUID NOT NULL REFERENCES risk_category(id),
    narrative_text TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'AiDrafted' CHECK (status IN ('AiDrafted','AnalystReviewed','AnalystEdited')),
    unsupported_claim_flags JSONB NOT NULL DEFAULT '[]'::jsonb, -- statements the drafting client could not trace to a supplied source/fact
    updated_by_user_id UUID REFERENCES app_user(id),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (assessment_id, risk_category_id)
);

-- ---- schema/010_scoring.sql ----
-- Epic 7 — Risk Scoring Engine + Epic 10's scoring-config half.
--
-- Residual Risk = Inherent Risk - (Control Effectiveness x Mitigation Factor), per CLAUDE.md.
-- inherent_rating is a 1-5 scale (Low..Very High) and max_mitigation_factor is capped strictly
-- below 1.0, so with control_effectiveness in [0,1]: residual = inherent - (effectiveness x
-- mitigation) > inherent - 1 >= 1 - 1 = 0. Residual risk reaching zero is therefore mathematically
-- impossible given these two constraints, not merely discouraged - enforced again below by the
-- CHECK on assessment_risk_score.residual_rating as defense in depth.

CREATE TABLE control (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    risk_category_id UUID REFERENCES risk_category(id),
    name TEXT NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Versioned: a config change is a new row, never an in-place update to a live one (US-10.1) - so
-- an assessment created before the change keeps scoring against the config that was active when
-- it started (assessment.scoring_config_version_id, wired up below).
CREATE TABLE scoring_config (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    risk_category_id UUID NOT NULL REFERENCES risk_category(id),
    max_mitigation_factor NUMERIC(4,3) NOT NULL CHECK (max_mitigation_factor >= 0 AND max_mitigation_factor < 1.0),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_by_user_id UUID NOT NULL REFERENCES app_user(id),
    reason TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE assessment
    ADD CONSTRAINT fk_assessment_scoring_config_version
    FOREIGN KEY (scoring_config_version_id) REFERENCES scoring_config(id);

CREATE TABLE assessment_risk_score (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assessment_id UUID NOT NULL REFERENCES assessment(id),
    risk_category_id UUID NOT NULL REFERENCES risk_category(id),
    inherent_rating NUMERIC(5,2) NOT NULL CHECK (inherent_rating >= 1 AND inherent_rating <= 5),
    control_ids_credited JSONB NOT NULL DEFAULT '[]'::jsonb,
    control_effectiveness NUMERIC(4,3) NOT NULL CHECK (control_effectiveness >= 0 AND control_effectiveness <= 1),
    mitigation_factor_applied NUMERIC(4,3) NOT NULL CHECK (mitigation_factor_applied >= 0 AND mitigation_factor_applied < 1.0),
    residual_rating NUMERIC(5,2) NOT NULL CHECK (residual_rating > 0),
    is_override BOOLEAN NOT NULL DEFAULT false,
    override_reason TEXT,
    scored_by TEXT NOT NULL CHECK (scored_by IN ('System','Analyst')),
    created_by_user_id UUID REFERENCES app_user(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (assessment_id, risk_category_id),
    CHECK (NOT is_override OR override_reason IS NOT NULL)
);

-- ---- schema/011_committee.sql ----
-- Epic 8 — schema only in this pass (see docs/architecture/architecture-mapping.md); no
-- Service/Controller wired yet, but the shape is settled so a later pass just adds code, not schema.

CREATE TABLE committee_vote (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assessment_id UUID NOT NULL REFERENCES assessment(id),
    committee_member_user_id UUID NOT NULL REFERENCES app_user(id),
    vote TEXT NOT NULL CHECK (vote IN ('Approve','Reject','Defer','ApproveWithConditions')),
    conditions_text TEXT,
    rationale TEXT,
    voted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (assessment_id, committee_member_user_id),
    CHECK (vote <> 'ApproveWithConditions' OR conditions_text IS NOT NULL),
    CHECK (vote NOT IN ('Reject','Defer') OR rationale IS NOT NULL)
);

CREATE TABLE committee_decision (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assessment_id UUID NOT NULL UNIQUE REFERENCES assessment(id),
    resolution TEXT NOT NULL CHECK (resolution IN ('Approved','Rejected','Deferred','ApprovedWithConditions')),
    conditions_text TEXT,
    decided_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---- schema/012_configuration.sql ----
-- Epic 10's workflow-rule half — schema only in this pass (the scoring-config half is
-- scoring_config in 010_scoring.sql, which IS wired end to end).

CREATE TABLE workflow_rule (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rule_key TEXT NOT NULL, -- e.g. 'RequiresCommitteeVote.Vendor', 'CommitteeQuorum', 'EscalationThreshold.ResidualRating'
    rule_value JSONB NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_by_user_id UUID NOT NULL REFERENCES app_user(id),
    reason TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---- schema/013_audit.sql ----
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

-- ---- schema/014_external_snapshot.sql ----
-- Phase 3 - Data Ingestion Layer. An immutable snapshot of whatever Mock External Systems context
-- (src/6-MockExternalSystems) was linked to a change request at submission time. Downstream (AI
-- clients, scoring, analyst UI) only ever reads this snapshot, never Mock Systems directly - see
-- docs/architecture/architecture-mapping.md's "Mock External Systems" section. UNIQUE on
-- change_request_id + no UPDATE path anywhere in functions/data_ingestion/ enforces "immutable":
-- a change request has no snapshot, or has exactly one, forever.

CREATE TABLE change_request_external_snapshot (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    change_request_id UUID NOT NULL UNIQUE REFERENCES change_request(id),
    mock_customer_id UUID,
    customer_risk_context JSONB,
    mock_product_id UUID,
    product_risk_context JSONB,
    mock_vendor_id UUID,
    vendor_risk_context JSONB,
    ingested_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================== functions ============================================

-- ---- functions/assessment/func_finalizeAssessment.sql ----
-- US-6.3: the completeness checks (no outstanding AI-drafted sections, etc.) run in
-- AssessmentService.Finalize BEFORE this is called, so this function only records the fact of
-- finalization - it does not re-validate readiness itself.
--
-- Deliberately does NOT move change_request to 'PendingCommittee' - US-8.1 treats "finalize" and
-- "route to committee" as two distinct analyst actions (see func_routeToCommittee.sql). Finalizing
-- only locks the assessment from further Product Owner edits (US-6.3 AC2); routing is what makes
-- it visible to the committee queue.
CREATE OR REPLACE FUNCTION func_finalizeAssessment(
    p_assessment_id UUID,
    p_actor_user_id UUID
) RETURNS VOID AS $$
DECLARE
    v_change_request_id UUID;
BEGIN
    SELECT change_request_id INTO v_change_request_id FROM assessment WHERE id = p_assessment_id;

    UPDATE assessment SET status = 'Finalized', finalized_by_user_id = p_actor_user_id, finalized_at = now()
    WHERE id = p_assessment_id;

    INSERT INTO audit_event (change_request_id, assessment_id, entity_type, entity_id, action, actor_user_id, actor_label, after_value)
    VALUES (v_change_request_id, p_assessment_id, 'Assessment', p_assessment_id, 'Finalized', p_actor_user_id, 'human',
            jsonb_build_object('finalizedBy', p_actor_user_id));
END;
$$ LANGUAGE plpgsql;

-- ---- functions/assessment/func_getAssessmentByChangeRequest.sql ----
CREATE OR REPLACE FUNCTION func_getAssessmentByChangeRequest(p_change_request_id UUID)
RETURNS TABLE (
    id UUID, change_request_id UUID, status TEXT,
    finalized_by_user_id UUID, finalized_at TIMESTAMPTZ, created_at TIMESTAMPTZ
) AS $$
    SELECT a.id, a.change_request_id, a.status, a.finalized_by_user_id, a.finalized_at, a.created_at
    FROM assessment a WHERE a.change_request_id = p_change_request_id;
$$ LANGUAGE sql STABLE;

-- ---- functions/assessment/func_getAssessmentById.sql ----
-- Used by NarrativeService (and anywhere else that only has an assessment_id) to resolve back to
-- its change_request_id - assessment_category_mapping/assessment_policy_reliance are keyed by
-- assessment_id, but extracted_field and the change request itself are keyed by change_request_id.
CREATE OR REPLACE FUNCTION func_getAssessmentById(p_assessment_id UUID)
RETURNS TABLE (
    id UUID, change_request_id UUID, status TEXT,
    finalized_by_user_id UUID, finalized_at TIMESTAMPTZ, created_at TIMESTAMPTZ
) AS $$
    SELECT a.id, a.change_request_id, a.status, a.finalized_by_user_id, a.finalized_at, a.created_at
    FROM assessment a WHERE a.id = p_assessment_id;
$$ LANGUAGE sql STABLE;

-- ---- functions/assessment/func_getOrCreateAssessment.sql ----
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

-- ---- functions/audit/func_appendAuditEvent.sql ----
-- Generic append, used directly by Services.Audit for events not already covered by a
-- domain-specific function above (e.g. AssessmentService cross-cutting events).
CREATE OR REPLACE FUNCTION func_appendAuditEvent(
    p_change_request_id UUID,
    p_assessment_id UUID,
    p_entity_type TEXT,
    p_entity_id UUID,
    p_action TEXT,
    p_actor_user_id UUID,
    p_actor_label TEXT,
    p_before_value JSONB,
    p_after_value JSONB,
    p_reason TEXT
) RETURNS UUID AS $$
DECLARE
    v_id UUID := gen_random_uuid();
BEGIN
    INSERT INTO audit_event (id, change_request_id, assessment_id, entity_type, entity_id, action, actor_user_id, actor_label, before_value, after_value, reason)
    VALUES (v_id, p_change_request_id, p_assessment_id, p_entity_type, p_entity_id, p_action, p_actor_user_id, COALESCE(p_actor_label, 'system/AI'), p_before_value, p_after_value, p_reason);
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- ---- functions/audit/func_getAuditTrailForRequest.sql ----
-- US-9.1: full chronological history for one change_request, across every module that wrote an
-- audit_event against either the request itself or its assessment.
--
-- before_value_json/after_value_json (not before_value/after_value) so Dapper maps them onto
-- AuditEvent.BeforeValueJson/AfterValueJson - see func_getChangeRequestById.sql's comment.
CREATE OR REPLACE FUNCTION func_getAuditTrailForRequest(p_change_request_id UUID)
RETURNS TABLE (
    id UUID, entity_type TEXT, entity_id UUID, action TEXT,
    actor_user_id UUID, actor_name TEXT, actor_label TEXT,
    before_value_json JSONB, after_value_json JSONB, reason TEXT, created_at TIMESTAMPTZ
) AS $$
    SELECT e.id, e.entity_type, e.entity_id, e.action, e.actor_user_id,
           u.display_name, e.actor_label, e.before_value, e.after_value, e.reason, e.created_at
    FROM audit_event e
    LEFT JOIN app_user u ON u.id = e.actor_user_id
    LEFT JOIN assessment a ON a.change_request_id = p_change_request_id
    WHERE e.change_request_id = p_change_request_id OR e.assessment_id = a.id
    ORDER BY e.created_at ASC;
$$ LANGUAGE sql STABLE;

-- ---- functions/category_mapping/func_getAllRiskCategories.sql ----
-- Needed by the frontend's "add a category" control (US-2.2) - an analyst can add any framework
-- category, not just the ones func_getChangeTypeCategoryDefaults would have suggested.
CREATE OR REPLACE FUNCTION func_getAllRiskCategories()
RETURNS TABLE (id UUID, code TEXT, name TEXT, citation_section TEXT) AS $$
    SELECT id, code, name, citation_section FROM risk_category ORDER BY name;
$$ LANGUAGE sql STABLE;

-- ---- functions/category_mapping/func_getCategoryMapping.sql ----
CREATE OR REPLACE FUNCTION func_getCategoryMapping(p_assessment_id UUID)
RETURNS TABLE (
    id UUID, risk_category_id UUID, category_code TEXT, category_name TEXT, citation_section TEXT,
    source TEXT, ai_citation TEXT, is_active BOOLEAN, created_at TIMESTAMPTZ
) AS $$
    SELECT m.id, m.risk_category_id, rc.code, rc.name, rc.citation_section, m.source, m.ai_citation, m.is_active, m.created_at
    FROM assessment_category_mapping m
    JOIN risk_category rc ON rc.id = m.risk_category_id
    WHERE m.assessment_id = p_assessment_id
    ORDER BY m.created_at;
$$ LANGUAGE sql STABLE;

-- ---- functions/category_mapping/func_getChangeTypeCategoryDefaults.sql ----
-- The grounding lookup CategoryMappingAiClient sends to Claude alongside the request details, so
-- the AI proposes from a fixed, named list rather than inventing categories (US-2.1 AC1).
CREATE OR REPLACE FUNCTION func_getChangeTypeCategoryDefaults(p_change_type TEXT)
RETURNS TABLE (risk_category_id UUID, code TEXT, name TEXT, citation_section TEXT, weight TEXT) AS $$
    SELECT rc.id, rc.code, rc.name, rc.citation_section, m.weight
    FROM change_request_type_category_map m
    JOIN risk_category rc ON rc.id = m.risk_category_id
    WHERE m.change_type = p_change_type
    ORDER BY m.weight; -- 'Primary' sorts before 'Secondary'
$$ LANGUAGE sql STABLE;

-- ---- functions/category_mapping/func_overrideCategoryMapping.sql ----
-- US-2.2: add/remove a category mapping; reason mandatory, original AI proposal never overwritten
-- (it stays in audit_event's before_value).
CREATE OR REPLACE FUNCTION func_overrideCategoryMapping(
    p_assessment_id UUID,
    p_risk_category_id UUID,
    p_is_active BOOLEAN, -- true = add, false = remove
    p_reason TEXT,
    p_actor_user_id UUID
) RETURNS UUID AS $$
DECLARE
    v_id UUID;
    v_before JSONB;
BEGIN
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'A reason is required to override a category mapping';
    END IF;

    SELECT to_jsonb(m) INTO v_before FROM assessment_category_mapping m
        WHERE assessment_id = p_assessment_id AND risk_category_id = p_risk_category_id;

    INSERT INTO assessment_category_mapping (assessment_id, risk_category_id, source, is_active, created_by_user_id)
    VALUES (p_assessment_id, p_risk_category_id, 'AnalystAdded', p_is_active, p_actor_user_id)
    ON CONFLICT (assessment_id, risk_category_id)
        DO UPDATE SET is_active = p_is_active, created_by_user_id = p_actor_user_id
    RETURNING id INTO v_id;

    INSERT INTO audit_event (assessment_id, entity_type, entity_id, action, actor_user_id, actor_label, before_value, after_value, reason)
    VALUES (p_assessment_id, 'CategoryMapping', v_id, 'Overridden', p_actor_user_id, 'human',
            v_before, jsonb_build_object('riskCategoryId', p_risk_category_id, 'isActive', p_is_active), p_reason);

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- ---- functions/category_mapping/func_saveCategoryMappingProposal.sql ----
-- US-2.1: called by the service layer after CategoryMappingAiClient (real Claude call) returns a
-- proposed category + citation. Actor is 'system/AI', not a user.
CREATE OR REPLACE FUNCTION func_saveCategoryMappingProposal(
    p_assessment_id UUID,
    p_risk_category_id UUID,
    p_ai_citation TEXT
) RETURNS UUID AS $$
DECLARE
    v_id UUID;
BEGIN
    INSERT INTO assessment_category_mapping (assessment_id, risk_category_id, source, ai_citation)
    VALUES (p_assessment_id, p_risk_category_id, 'AiProposed', p_ai_citation)
    ON CONFLICT (assessment_id, risk_category_id) DO UPDATE SET ai_citation = EXCLUDED.ai_citation
    RETURNING id INTO v_id;

    INSERT INTO audit_event (assessment_id, entity_type, entity_id, action, actor_label, after_value)
    VALUES (p_assessment_id, 'CategoryMapping', v_id, 'AiProposed', 'system/AI',
            jsonb_build_object('riskCategoryId', p_risk_category_id, 'citation', p_ai_citation));

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- ---- functions/change_requests/func_attachDocument.sql ----
-- US-1.2: replacing a document creates a new versioned row, never overwrites the old one.
CREATE OR REPLACE FUNCTION func_attachDocument(
    p_change_request_id UUID,
    p_file_name TEXT,
    p_content_type TEXT,
    p_storage_path TEXT,
    p_extracted_text TEXT,
    p_uploaded_by_user_id UUID,
    p_supersedes_attachment_id UUID DEFAULT NULL
) RETURNS TABLE (id UUID, version_number INT) AS $$
DECLARE
    v_id UUID := gen_random_uuid();
    v_version INT := 1;
BEGIN
    IF p_supersedes_attachment_id IS NOT NULL THEN
        SELECT a.version_number + 1 INTO v_version FROM change_request_attachment a WHERE a.id = p_supersedes_attachment_id;
    END IF;

    INSERT INTO change_request_attachment (id, change_request_id, file_name, content_type, storage_path, extracted_text, version_number, uploaded_by_user_id)
    VALUES (v_id, p_change_request_id, p_file_name, p_content_type, p_storage_path, p_extracted_text, v_version, p_uploaded_by_user_id);

    IF p_supersedes_attachment_id IS NOT NULL THEN
        UPDATE change_request_attachment SET superseded_by_attachment_id = v_id WHERE id = p_supersedes_attachment_id;
    END IF;

    INSERT INTO audit_event (change_request_id, entity_type, entity_id, action, actor_user_id, actor_label, after_value)
    VALUES (p_change_request_id, 'Attachment', v_id, 'Uploaded', p_uploaded_by_user_id, 'human',
            jsonb_build_object('fileName', p_file_name, 'version', v_version));

    RETURN QUERY SELECT v_id, v_version;
END;
$$ LANGUAGE plpgsql;

-- ---- functions/change_requests/func_createChangeRequest.sql ----
CREATE OR REPLACE FUNCTION func_createChangeRequest(
    p_change_type TEXT,
    p_title TEXT,
    p_description TEXT,
    p_type_specific_fields JSONB,
    p_submitted_by_user_id UUID
) RETURNS TABLE (id UUID, request_number TEXT, status TEXT, submitted_at TIMESTAMPTZ) AS $$
DECLARE
    v_id UUID := gen_random_uuid();
    v_request_number TEXT := 'CR-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('change_request_number_seq')::text, 5, '0');
BEGIN
    INSERT INTO change_request (id, request_number, change_type, title, description, type_specific_fields, submitted_by_user_id)
    VALUES (v_id, v_request_number, p_change_type, p_title, p_description, COALESCE(p_type_specific_fields, '{}'::jsonb), p_submitted_by_user_id);

    INSERT INTO audit_event (change_request_id, entity_type, entity_id, action, actor_user_id, actor_label, after_value)
    VALUES (v_id, 'ChangeRequest', v_id, 'Created', p_submitted_by_user_id, 'human',
            jsonb_build_object('changeType', p_change_type, 'title', p_title, 'status', 'Submitted'));

    RETURN QUERY SELECT c.id, c.request_number, c.status, c.submitted_at FROM change_request c WHERE c.id = v_id;
END;
$$ LANGUAGE plpgsql;

-- ---- functions/change_requests/func_getAllChangeRequests.sql ----
-- The analyst-facing inbox - "every submitted change request", not scoped to one submitter.
-- Mirrors func_getChangeRequestsForUser.sql minus the WHERE.
CREATE OR REPLACE FUNCTION func_getAllChangeRequests()
RETURNS TABLE (
    id UUID, request_number TEXT, change_type TEXT, title TEXT, status TEXT,
    submitted_at TIMESTAMPTZ, days_elapsed INT
) AS $$
    SELECT c.id, c.request_number, c.change_type, c.title, c.status, c.submitted_at,
           EXTRACT(DAY FROM now() - c.submitted_at)::INT AS days_elapsed
    FROM change_request c
    ORDER BY c.submitted_at DESC;
$$ LANGUAGE sql STABLE;

-- ---- functions/change_requests/func_getAttachments.sql ----
CREATE OR REPLACE FUNCTION func_getAttachments(p_change_request_id UUID)
RETURNS TABLE (id UUID, file_name TEXT, content_type TEXT, storage_path TEXT, version_number INT, uploaded_at TIMESTAMPTZ) AS $$
    SELECT a.id, a.file_name, a.content_type, a.storage_path, a.version_number, a.uploaded_at
    FROM change_request_attachment a
    WHERE a.change_request_id = p_change_request_id AND a.superseded_by_attachment_id IS NULL
    ORDER BY a.uploaded_at;
$$ LANGUAGE sql STABLE;

-- ---- functions/change_requests/func_getChangeRequestById.sql ----
-- Output column is named type_specific_fields_json (not type_specific_fields) so Dapper's
-- MatchNamesWithUnderscores maps it onto ChangeRequest.TypeSpecificFieldsJson - RETURNS TABLE
-- column names become the actual result-set column names regardless of the SELECT body's own
-- aliases, so this rename alone is enough; the SELECT below is unchanged.
CREATE OR REPLACE FUNCTION func_getChangeRequestById(p_change_request_id UUID)
RETURNS TABLE (
    id UUID, request_number TEXT, change_type TEXT, title TEXT, description TEXT,
    type_specific_fields_json JSONB, status TEXT, submitted_by_user_id UUID, submitted_at TIMESTAMPTZ
) AS $$
    SELECT c.id, c.request_number, c.change_type, c.title, c.description, c.type_specific_fields,
           c.status, c.submitted_by_user_id, c.submitted_at
    FROM change_request c WHERE c.id = p_change_request_id;
$$ LANGUAGE sql STABLE;

-- ---- functions/change_requests/func_getChangeRequestsForUser.sql ----
-- US-1.3: "all my requests with current status and days elapsed since submission."
CREATE OR REPLACE FUNCTION func_getChangeRequestsForUser(p_user_id UUID)
RETURNS TABLE (
    id UUID, request_number TEXT, change_type TEXT, title TEXT, status TEXT,
    submitted_at TIMESTAMPTZ, days_elapsed INT
) AS $$
    SELECT c.id, c.request_number, c.change_type, c.title, c.status, c.submitted_at,
           EXTRACT(DAY FROM now() - c.submitted_at)::INT AS days_elapsed
    FROM change_request c
    WHERE c.submitted_by_user_id = p_user_id
    ORDER BY c.submitted_at DESC;
$$ LANGUAGE sql STABLE;

-- ---- functions/change_requests/func_requestClarification.sql ----
CREATE OR REPLACE FUNCTION func_requestClarification(
    p_change_request_id UUID,
    p_requested_by_user_id UUID,
    p_question TEXT
) RETURNS UUID AS $$
DECLARE
    v_id UUID := gen_random_uuid();
BEGIN
    INSERT INTO change_request_clarification (id, change_request_id, requested_by_user_id, question)
    VALUES (v_id, p_change_request_id, p_requested_by_user_id, p_question);

    INSERT INTO audit_event (change_request_id, entity_type, entity_id, action, actor_user_id, actor_label, after_value)
    VALUES (p_change_request_id, 'Clarification', v_id, 'Requested', p_requested_by_user_id, 'human',
            jsonb_build_object('question', p_question));

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- ---- functions/change_requests/func_updateChangeRequestStatus.sql ----
CREATE OR REPLACE FUNCTION func_updateChangeRequestStatus(
    p_change_request_id UUID,
    p_new_status TEXT,
    p_actor_user_id UUID
) RETURNS VOID AS $$
DECLARE
    v_old_status TEXT;
BEGIN
    SELECT status INTO v_old_status FROM change_request WHERE id = p_change_request_id;

    UPDATE change_request SET status = p_new_status WHERE id = p_change_request_id;

    INSERT INTO audit_event (change_request_id, entity_type, entity_id, action, actor_user_id, actor_label, before_value, after_value)
    VALUES (p_change_request_id, 'ChangeRequest', p_change_request_id, 'StatusChanged', p_actor_user_id,
            CASE WHEN p_actor_user_id IS NULL THEN 'system/AI' ELSE 'human' END,
            jsonb_build_object('status', v_old_status), jsonb_build_object('status', p_new_status));
END;
$$ LANGUAGE plpgsql;

-- ---- functions/committee/func_castCommitteeVote.sql ----
-- US-8.2: one row per member per assessment - votes are never aggregated into a single record
-- (AC5), each stays individually attributable. committee_vote's own CHECK constraints
-- (schema/011_committee.sql) already enforce conditions_text/rationale being present for the vote
-- types that require them, so this function doesn't need to re-validate that.
CREATE OR REPLACE FUNCTION func_castCommitteeVote(
    p_assessment_id UUID,
    p_committee_member_user_id UUID,
    p_vote TEXT,
    p_conditions_text TEXT,
    p_rationale TEXT
) RETURNS UUID AS $$
DECLARE
    v_id UUID;
    v_change_request_id UUID;
BEGIN
    SELECT change_request_id INTO v_change_request_id FROM assessment WHERE id = p_assessment_id;

    INSERT INTO committee_vote (assessment_id, committee_member_user_id, vote, conditions_text, rationale)
    VALUES (p_assessment_id, p_committee_member_user_id, p_vote, p_conditions_text, p_rationale)
    ON CONFLICT (assessment_id, committee_member_user_id) DO UPDATE SET
        vote = EXCLUDED.vote, conditions_text = EXCLUDED.conditions_text, rationale = EXCLUDED.rationale, voted_at = now()
    RETURNING id INTO v_id;

    INSERT INTO audit_event (change_request_id, assessment_id, entity_type, entity_id, action, actor_user_id, actor_label, after_value)
    VALUES (v_change_request_id, p_assessment_id, 'CommitteeVote', v_id, 'Voted', p_committee_member_user_id, 'human',
            jsonb_build_object('vote', p_vote, 'conditionsText', p_conditions_text, 'rationale', p_rationale));

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- ---- functions/committee/func_getCommitteeDecision.sql ----
-- US-8.3 AC3: conditions stay visibly attached to the request record for future reference, not
-- just buried in a vote comment.
CREATE OR REPLACE FUNCTION func_getCommitteeDecision(p_assessment_id UUID)
RETURNS TABLE (id UUID, resolution TEXT, conditions_text TEXT, decided_at TIMESTAMPTZ) AS $$
    SELECT d.id, d.resolution, d.conditions_text, d.decided_at
    FROM committee_decision d WHERE d.assessment_id = p_assessment_id;
$$ LANGUAGE sql STABLE;

-- ---- functions/committee/func_getCommitteeQueue.sql ----
-- US-8.1 AC1: everything currently sitting in the committee's decision queue.
CREATE OR REPLACE FUNCTION func_getCommitteeQueue()
RETURNS TABLE (
    assessment_id UUID, change_request_id UUID, request_number TEXT,
    change_type TEXT, title TEXT, routed_at TIMESTAMPTZ
) AS $$
    SELECT a.id, c.id, c.request_number, c.change_type, c.title, a.finalized_at
    FROM change_request c
    JOIN assessment a ON a.change_request_id = c.id
    WHERE c.status = 'PendingCommittee'
    ORDER BY a.finalized_at;
$$ LANGUAGE sql STABLE;

-- ---- functions/committee/func_getCommitteeVotes.sql ----
CREATE OR REPLACE FUNCTION func_getCommitteeVotes(p_assessment_id UUID)
RETURNS TABLE (
    id UUID, committee_member_user_id UUID, committee_member_name TEXT,
    vote TEXT, conditions_text TEXT, rationale TEXT, voted_at TIMESTAMPTZ
) AS $$
    SELECT v.id, v.committee_member_user_id, u.display_name, v.vote, v.conditions_text, v.rationale, v.voted_at
    FROM committee_vote v
    JOIN app_user u ON u.id = v.committee_member_user_id
    WHERE v.assessment_id = p_assessment_id
    ORDER BY v.voted_at;
$$ LANGUAGE sql STABLE;

-- ---- functions/committee/func_recordCommitteeDecision.sql ----
-- US-8.3: the resolution itself (majority/unanimous/quorum rule) is computed in
-- CommitteeService.cs, reading the "CommitteeQuorum" workflow_rule (Epic 10 tie-in) - this
-- function only persists the already-decided outcome and updates the request's broad status.
--
-- change_request.status moves to 'Decisioned' (not the specific resolution value) to stay inside
-- the four broad statuses Epic 1 tracks (US-1.1); the specific resolution + any conditions live in
-- committee_decision, read via func_getCommitteeDecision.
CREATE OR REPLACE FUNCTION func_recordCommitteeDecision(
    p_assessment_id UUID,
    p_resolution TEXT,
    p_conditions_text TEXT
) RETURNS UUID AS $$
DECLARE
    v_id UUID := gen_random_uuid();
    v_change_request_id UUID;
BEGIN
    SELECT change_request_id INTO v_change_request_id FROM assessment WHERE id = p_assessment_id;

    INSERT INTO committee_decision (id, assessment_id, resolution, conditions_text)
    VALUES (v_id, p_assessment_id, p_resolution, p_conditions_text);

    UPDATE change_request SET status = 'Decisioned' WHERE id = v_change_request_id;

    INSERT INTO audit_event (change_request_id, assessment_id, entity_type, entity_id, action, actor_label, after_value)
    VALUES (v_change_request_id, p_assessment_id, 'CommitteeDecision', v_id, 'Decisioned', 'system/AI',
            jsonb_build_object('resolution', p_resolution, 'conditionsText', p_conditions_text));

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- ---- functions/committee/func_routeToCommittee.sql ----
-- US-8.1: moves a Finalized assessment's change request into the committee queue. Distinct from
-- finalization itself (func_finalizeAssessment) - see that file's comment.
CREATE OR REPLACE FUNCTION func_routeToCommittee(
    p_assessment_id UUID,
    p_actor_user_id UUID
) RETURNS VOID AS $$
DECLARE
    v_change_request_id UUID;
    v_assessment_status TEXT;
BEGIN
    SELECT change_request_id, status INTO v_change_request_id, v_assessment_status
    FROM assessment WHERE id = p_assessment_id;

    IF v_assessment_status IS DISTINCT FROM 'Finalized' THEN
        RAISE EXCEPTION 'Assessment % must be Finalized before it can be routed to committee (current status: %)',
            p_assessment_id, v_assessment_status;
    END IF;

    UPDATE change_request SET status = 'PendingCommittee' WHERE id = v_change_request_id;

    INSERT INTO audit_event (change_request_id, assessment_id, entity_type, entity_id, action, actor_user_id, actor_label, after_value)
    VALUES (v_change_request_id, p_assessment_id, 'ChangeRequest', v_change_request_id, 'Routed', p_actor_user_id, 'human',
            jsonb_build_object('status', 'PendingCommittee'));
END;
$$ LANGUAGE plpgsql;

-- ---- functions/configuration/func_getAllActiveWorkflowRules.sql ----
-- US-10.2 AC1: "current rules in plain, structured form" - the whole active set, not buried in code.
-- rule_value_json (not rule_value) so Dapper maps it onto WorkflowRule.RuleValueJson.
CREATE OR REPLACE FUNCTION func_getAllActiveWorkflowRules()
RETURNS TABLE (id UUID, rule_key TEXT, rule_value_json JSONB, is_active BOOLEAN, created_at TIMESTAMPTZ) AS $$
    SELECT id, rule_key, rule_value, is_active, created_at
    FROM workflow_rule WHERE is_active = true
    ORDER BY rule_key;
$$ LANGUAGE sql STABLE;

-- ---- functions/configuration/func_getWorkflowRule.sql ----
-- rule_value_json (not rule_value) so Dapper maps it onto WorkflowRule.RuleValueJson - see
-- func_getChangeRequestById.sql's comment.
CREATE OR REPLACE FUNCTION func_getWorkflowRule(p_rule_key TEXT)
RETURNS TABLE (id UUID, rule_key TEXT, rule_value_json JSONB, is_active BOOLEAN, created_at TIMESTAMPTZ) AS $$
    SELECT id, rule_key, rule_value, is_active, created_at
    FROM workflow_rule WHERE rule_key = p_rule_key AND is_active = true;
$$ LANGUAGE sql STABLE;

-- ---- functions/configuration/func_upsertWorkflowRule.sql ----
-- US-10.2: a rule change is a new versioned row (never an in-place update), so in-flight requests
-- keep following the rule that was active when they were submitted, unless explicitly re-queried
-- against the new one - same versioning pattern as scoring_config (schema/010_scoring.sql).
CREATE OR REPLACE FUNCTION func_upsertWorkflowRule(
    p_rule_key TEXT,
    p_rule_value JSONB,
    p_reason TEXT,
    p_actor_user_id UUID
) RETURNS UUID AS $$
DECLARE
    v_id UUID := gen_random_uuid();
BEGIN
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'A reason is required to change a workflow rule';
    END IF;

    UPDATE workflow_rule SET is_active = false WHERE rule_key = p_rule_key AND is_active = true;

    INSERT INTO workflow_rule (id, rule_key, rule_value, created_by_user_id, reason)
    VALUES (v_id, p_rule_key, p_rule_value, p_actor_user_id, p_reason);

    INSERT INTO audit_event (entity_type, entity_id, action, actor_user_id, actor_label, after_value, reason)
    VALUES ('WorkflowRule', v_id, 'ConfigChanged', p_actor_user_id, 'human',
            jsonb_build_object('ruleKey', p_rule_key, 'ruleValue', p_rule_value), p_reason);

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- ---- functions/data_ingestion/func_getExternalSnapshot.sql ----
CREATE OR REPLACE FUNCTION func_getExternalSnapshot(p_change_request_id UUID)
RETURNS TABLE (
    id UUID,
    change_request_id UUID,
    mock_customer_id UUID,
    customer_risk_context_json JSONB,
    mock_product_id UUID,
    product_risk_context_json JSONB,
    mock_vendor_id UUID,
    vendor_risk_context_json JSONB,
    ingested_at TIMESTAMPTZ
) AS $$
    SELECT
        s.id, s.change_request_id,
        s.mock_customer_id, s.customer_risk_context,
        s.mock_product_id, s.product_risk_context,
        s.mock_vendor_id, s.vendor_risk_context,
        s.ingested_at
    FROM change_request_external_snapshot s
    WHERE s.change_request_id = p_change_request_id;
$$ LANGUAGE sql;

-- ---- functions/data_ingestion/func_saveExternalSnapshot.sql ----
CREATE OR REPLACE FUNCTION func_saveExternalSnapshot(
    p_change_request_id UUID,
    p_mock_customer_id UUID,
    p_customer_risk_context JSONB,
    p_mock_product_id UUID,
    p_product_risk_context JSONB,
    p_mock_vendor_id UUID,
    p_vendor_risk_context JSONB
) RETURNS TABLE (id UUID, ingested_at TIMESTAMPTZ) AS $$
BEGIN
    INSERT INTO change_request_external_snapshot (
        change_request_id, mock_customer_id, customer_risk_context,
        mock_product_id, product_risk_context, mock_vendor_id, vendor_risk_context
    ) VALUES (
        p_change_request_id, p_mock_customer_id, p_customer_risk_context,
        p_mock_product_id, p_product_risk_context, p_mock_vendor_id, p_vendor_risk_context
    )
    ON CONFLICT (change_request_id) DO NOTHING; -- immutable: never overwrite an existing snapshot

    INSERT INTO audit_event (change_request_id, entity_type, entity_id, action, actor_label, after_value)
    VALUES (p_change_request_id, 'ExternalSnapshot', p_change_request_id, 'Ingested', 'system',
            jsonb_build_object(
                'hasCustomer', p_mock_customer_id IS NOT NULL,
                'hasProduct', p_mock_product_id IS NOT NULL,
                'hasVendor', p_mock_vendor_id IS NOT NULL));

    RETURN QUERY SELECT s.id, s.ingested_at FROM change_request_external_snapshot s WHERE s.change_request_id = p_change_request_id;
END;
$$ LANGUAGE plpgsql;

-- ---- functions/extraction/func_correctExtractedField.sql ----
-- US-4.2: reason is only mandatory when the edit materially changes the field's meaning - that
-- judgment call is made by the service layer (Services/DocumentExtraction), not here, so p_reason
-- is nullable at the DB level.
CREATE OR REPLACE FUNCTION func_correctExtractedField(
    p_change_request_id UUID,
    p_field_key TEXT,
    p_new_value TEXT,
    p_reason TEXT,
    p_actor_user_id UUID
) RETURNS UUID AS $$
DECLARE
    v_id UUID;
    v_before JSONB;
BEGIN
    SELECT to_jsonb(f) INTO v_before FROM extracted_field f WHERE change_request_id = p_change_request_id AND field_key = p_field_key;

    UPDATE extracted_field
    SET field_value = p_new_value, source = 'AnalystCorrected', needs_review = false,
        confidence = NULL, updated_by_user_id = p_actor_user_id, updated_at = now()
    WHERE change_request_id = p_change_request_id AND field_key = p_field_key
    RETURNING id INTO v_id;

    INSERT INTO audit_event (change_request_id, entity_type, entity_id, action, actor_user_id, actor_label, before_value, after_value, reason)
    VALUES (p_change_request_id, 'ExtractedField', v_id, 'Corrected', p_actor_user_id, 'human',
            v_before, jsonb_build_object('fieldKey', p_field_key, 'value', p_new_value), p_reason);

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- ---- functions/extraction/func_getExtractedFields.sql ----
CREATE OR REPLACE FUNCTION func_getExtractedFields(p_change_request_id UUID)
RETURNS TABLE (
    id UUID, field_key TEXT, field_value TEXT, confidence NUMERIC,
    needs_review BOOLEAN, source_excerpt TEXT, source TEXT, updated_at TIMESTAMPTZ
) AS $$
    SELECT f.id, f.field_key, f.field_value, f.confidence, f.needs_review, f.source_excerpt, f.source, f.updated_at
    FROM extracted_field f WHERE f.change_request_id = p_change_request_id;
$$ LANGUAGE sql STABLE;

-- ---- functions/extraction/func_saveExtractedField.sql ----
-- US-4.1: DocumentExtractionAiClient (real Claude call) writes one row per structured field.
CREATE OR REPLACE FUNCTION func_saveExtractedField(
    p_change_request_id UUID,
    p_attachment_id UUID,
    p_field_key TEXT,
    p_field_value TEXT,
    p_confidence NUMERIC,
    p_needs_review BOOLEAN,
    p_source_excerpt TEXT
) RETURNS UUID AS $$
DECLARE
    v_id UUID;
BEGIN
    INSERT INTO extracted_field (change_request_id, attachment_id, field_key, field_value, confidence, needs_review, source_excerpt, source)
    VALUES (p_change_request_id, p_attachment_id, p_field_key, p_field_value, p_confidence, p_needs_review, p_source_excerpt, 'AiExtracted')
    ON CONFLICT (change_request_id, field_key) DO UPDATE SET
        field_value = EXCLUDED.field_value, confidence = EXCLUDED.confidence,
        needs_review = EXCLUDED.needs_review, source_excerpt = EXCLUDED.source_excerpt,
        source = 'AiExtracted', updated_at = now()
    RETURNING id INTO v_id;

    INSERT INTO audit_event (change_request_id, entity_type, entity_id, action, actor_label, after_value)
    VALUES (p_change_request_id, 'ExtractedField', v_id, 'AiExtracted', 'system/AI',
            jsonb_build_object('fieldKey', p_field_key, 'value', p_field_value, 'confidence', p_confidence, 'needsReview', p_needs_review));

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- ---- functions/narrative/func_editNarrativeSection.sql ----
-- US-6.1: any edit to AI-generated narrative text requires a reason; original stays in
-- audit_event.before_value.
CREATE OR REPLACE FUNCTION func_editNarrativeSection(
    p_assessment_id UUID,
    p_risk_category_id UUID,
    p_new_text TEXT,
    p_reason TEXT,
    p_actor_user_id UUID
) RETURNS UUID AS $$
DECLARE
    v_id UUID;
    v_before JSONB;
BEGIN
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'A reason is required to edit an AI-drafted narrative section';
    END IF;

    SELECT to_jsonb(s) INTO v_before FROM assessment_narrative_section s
        WHERE assessment_id = p_assessment_id AND risk_category_id = p_risk_category_id;

    UPDATE assessment_narrative_section
    SET narrative_text = p_new_text, status = 'AnalystEdited', updated_by_user_id = p_actor_user_id, updated_at = now()
    WHERE assessment_id = p_assessment_id AND risk_category_id = p_risk_category_id
    RETURNING id INTO v_id;

    INSERT INTO audit_event (assessment_id, entity_type, entity_id, action, actor_user_id, actor_label, before_value, after_value, reason)
    VALUES (p_assessment_id, 'NarrativeSection', v_id, 'AnalystEdited', p_actor_user_id, 'human',
            v_before, jsonb_build_object('riskCategoryId', p_risk_category_id, 'text', p_new_text), p_reason);

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- ---- functions/narrative/func_getNarrativeSections.sql ----
-- unsupported_claim_flags_json (not unsupported_claim_flags) so Dapper maps it onto
-- NarrativeSection.UnsupportedClaimFlagsJson - see func_getChangeRequestById.sql's comment.
CREATE OR REPLACE FUNCTION func_getNarrativeSections(p_assessment_id UUID)
RETURNS TABLE (
    id UUID, risk_category_id UUID, category_name TEXT, narrative_text TEXT,
    status TEXT, unsupported_claim_flags_json JSONB, updated_at TIMESTAMPTZ
) AS $$
    SELECT s.id, s.risk_category_id, rc.name, s.narrative_text, s.status, s.unsupported_claim_flags, s.updated_at
    FROM assessment_narrative_section s
    JOIN risk_category rc ON rc.id = s.risk_category_id
    WHERE s.assessment_id = p_assessment_id;
$$ LANGUAGE sql STABLE;

-- ---- functions/narrative/func_reviewNarrativeSection.sql ----
-- US-6.3: analyst accepts an AI-drafted section as-is (no text change, so no reason required -
-- accepting isn't an edit). Compare func_editNarrativeSection.sql for the edit path.
CREATE OR REPLACE FUNCTION func_reviewNarrativeSection(
    p_assessment_id UUID,
    p_risk_category_id UUID,
    p_actor_user_id UUID
) RETURNS UUID AS $$
DECLARE
    v_id UUID;
BEGIN
    UPDATE assessment_narrative_section
    SET status = 'AnalystReviewed', updated_by_user_id = p_actor_user_id, updated_at = now()
    WHERE assessment_id = p_assessment_id AND risk_category_id = p_risk_category_id
    RETURNING id INTO v_id;

    INSERT INTO audit_event (assessment_id, entity_type, entity_id, action, actor_user_id, actor_label, after_value)
    VALUES (p_assessment_id, 'NarrativeSection', v_id, 'AnalystReviewed', p_actor_user_id, 'human',
            jsonb_build_object('riskCategoryId', p_risk_category_id, 'status', 'AnalystReviewed'));

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- ---- functions/narrative/func_saveNarrativeSection.sql ----
-- US-5.1/US-5.2: (re)draft one category's narrative. Used for both the first AI draft and a
-- "regenerate with feedback" call - both are the AI producing a new AiDrafted version; the prior
-- text is preserved in audit_event.before_value, never lost (US-5.2 AC2).
CREATE OR REPLACE FUNCTION func_saveNarrativeSection(
    p_assessment_id UUID,
    p_risk_category_id UUID,
    p_narrative_text TEXT,
    p_unsupported_claim_flags JSONB
) RETURNS UUID AS $$
DECLARE
    v_id UUID;
    v_before JSONB;
BEGIN
    SELECT to_jsonb(s) INTO v_before FROM assessment_narrative_section s
        WHERE assessment_id = p_assessment_id AND risk_category_id = p_risk_category_id;

    INSERT INTO assessment_narrative_section (assessment_id, risk_category_id, narrative_text, unsupported_claim_flags, status)
    VALUES (p_assessment_id, p_risk_category_id, p_narrative_text, COALESCE(p_unsupported_claim_flags, '[]'::jsonb), 'AiDrafted')
    ON CONFLICT (assessment_id, risk_category_id) DO UPDATE SET
        narrative_text = EXCLUDED.narrative_text, unsupported_claim_flags = EXCLUDED.unsupported_claim_flags,
        status = 'AiDrafted', updated_by_user_id = NULL, updated_at = now()
    RETURNING id INTO v_id;

    INSERT INTO audit_event (assessment_id, entity_type, entity_id, action, actor_label, before_value, after_value)
    VALUES (p_assessment_id, 'NarrativeSection', v_id, 'AiDrafted', 'system/AI',
            v_before, jsonb_build_object('riskCategoryId', p_risk_category_id, 'text', p_narrative_text));

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- ---- functions/policy_research/func_getPolicyReliance.sql ----
-- Used by AssessmentService.Finalize to enforce US-3.2 AC2: at least one reviewed policy per
-- mapped risk category before finalization is allowed.
CREATE OR REPLACE FUNCTION func_getPolicyReliance(p_assessment_id UUID)
RETURNS TABLE (
    id UUID, risk_category_id UUID, policy_chunk_id UUID, decision TEXT, decided_at TIMESTAMPTZ,
    section_ref TEXT, chunk_text TEXT
) AS $$
    SELECT r.id, r.risk_category_id, r.policy_chunk_id, r.decision, r.decided_at, pc.section_ref, pc.chunk_text
    FROM assessment_policy_reliance r
    JOIN policy_chunk pc ON pc.id = r.policy_chunk_id
    WHERE r.assessment_id = p_assessment_id;
$$ LANGUAGE sql STABLE;

-- ---- functions/policy_research/func_recordPolicyReliance.sql ----
-- US-3.2: mark a surfaced policy chunk relied-upon / not-relevant.
CREATE OR REPLACE FUNCTION func_recordPolicyReliance(
    p_assessment_id UUID,
    p_risk_category_id UUID,
    p_policy_chunk_id UUID,
    p_decision TEXT,
    p_decided_by_user_id UUID
) RETURNS UUID AS $$
DECLARE
    v_id UUID;
BEGIN
    INSERT INTO assessment_policy_reliance (assessment_id, risk_category_id, policy_chunk_id, decision, decided_by_user_id)
    VALUES (p_assessment_id, p_risk_category_id, p_policy_chunk_id, p_decision, p_decided_by_user_id)
    ON CONFLICT (assessment_id, policy_chunk_id)
        DO UPDATE SET decision = EXCLUDED.decision, decided_by_user_id = EXCLUDED.decided_by_user_id, decided_at = now()
    RETURNING id INTO v_id;

    INSERT INTO audit_event (assessment_id, entity_type, entity_id, action, actor_user_id, actor_label, after_value)
    VALUES (p_assessment_id, 'PolicyReliance', v_id, 'Decided', p_decided_by_user_id, 'human',
            jsonb_build_object('policyChunkId', p_policy_chunk_id, 'decision', p_decision));

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- ---- functions/policy_research/func_searchPolicyChunks.sql ----
-- US-3.1: deterministic Postgres full-text search - deliberately NOT an LLM/embedding call.
-- Ranking policy text by keyword relevance is a solved search problem; spending an LLM call on it
-- would add latency/cost/nondeterminism for no accuracy gain. See
-- docs/governance/human-in-the-loop-gates.md.
CREATE OR REPLACE FUNCTION func_searchPolicyChunks(
    p_query_text TEXT,
    p_risk_category_id UUID DEFAULT NULL,
    p_top_k INT DEFAULT 5
) RETURNS TABLE (
    id UUID, policy_document_id UUID, document_title TEXT, source_url TEXT, effective_date DATE,
    section_ref TEXT, chunk_text TEXT, rank REAL
) AS $$
    SELECT pc.id, pc.policy_document_id, pd.title, pd.source_url, pd.effective_date, pc.section_ref, pc.chunk_text,
           ts_rank(pc.search_vector, plainto_tsquery('english', p_query_text)) AS rank
    FROM policy_chunk pc
    JOIN policy_document pd ON pd.id = pc.policy_document_id
    WHERE (p_risk_category_id IS NULL OR pc.risk_category_id = p_risk_category_id)
      AND pc.search_vector @@ plainto_tsquery('english', p_query_text)
    ORDER BY rank DESC
    LIMIT p_top_k;
$$ LANGUAGE sql STABLE;

-- ---- functions/scoring/func_calculateAndSaveRiskScore.sql ----
-- US-7.1: Residual Risk = Inherent Risk - (Control Effectiveness x Mitigation Factor). Purely
-- deterministic - no LLM involved in the calculation itself. See schema/010_scoring.sql for why
-- this can never reach zero given the table's own constraints.
CREATE OR REPLACE FUNCTION func_calculateAndSaveRiskScore(
    p_assessment_id UUID,
    p_risk_category_id UUID,
    p_inherent_rating NUMERIC,
    p_control_ids_credited JSONB,
    p_control_effectiveness NUMERIC
) RETURNS TABLE (id UUID, residual_rating NUMERIC, mitigation_factor_applied NUMERIC) AS $$
DECLARE
    v_id UUID;
    v_mitigation_factor NUMERIC;
    v_residual NUMERIC;
BEGIN
    SELECT max_mitigation_factor INTO v_mitigation_factor
    FROM scoring_config WHERE risk_category_id = p_risk_category_id AND is_active = true;

    IF v_mitigation_factor IS NULL THEN
        RAISE EXCEPTION 'No active scoring configuration for risk category %', p_risk_category_id;
    END IF;

    v_residual := p_inherent_rating - (p_control_effectiveness * v_mitigation_factor);

    INSERT INTO assessment_risk_score (
        id, assessment_id, risk_category_id, inherent_rating, control_ids_credited,
        control_effectiveness, mitigation_factor_applied, residual_rating, is_override, scored_by
    ) VALUES (
        gen_random_uuid(), p_assessment_id, p_risk_category_id, p_inherent_rating, COALESCE(p_control_ids_credited, '[]'::jsonb),
        p_control_effectiveness, v_mitigation_factor, v_residual, false, 'System'
    )
    ON CONFLICT (assessment_id, risk_category_id) DO UPDATE SET
        inherent_rating = EXCLUDED.inherent_rating, control_ids_credited = EXCLUDED.control_ids_credited,
        control_effectiveness = EXCLUDED.control_effectiveness, mitigation_factor_applied = EXCLUDED.mitigation_factor_applied,
        residual_rating = EXCLUDED.residual_rating, is_override = false, override_reason = NULL,
        scored_by = 'System', created_at = now()
    RETURNING assessment_risk_score.id INTO v_id;

    INSERT INTO audit_event (assessment_id, entity_type, entity_id, action, actor_label, after_value)
    VALUES (p_assessment_id, 'RiskScore', v_id, 'Calculated', 'system/AI',
            jsonb_build_object('riskCategoryId', p_risk_category_id, 'inherent', p_inherent_rating, 'residual', v_residual));

    RETURN QUERY SELECT v_id, v_residual, v_mitigation_factor;
END;
$$ LANGUAGE plpgsql;

-- ---- functions/scoring/func_getControls.sql ----
CREATE OR REPLACE FUNCTION func_getControls(p_risk_category_id UUID)
RETURNS TABLE (id UUID, name TEXT, description TEXT) AS $$
    SELECT c.id, c.name, c.description FROM control c WHERE c.risk_category_id = p_risk_category_id;
$$ LANGUAGE sql STABLE;

-- ---- functions/scoring/func_getRiskScores.sql ----
CREATE OR REPLACE FUNCTION func_getRiskScores(p_assessment_id UUID)
RETURNS TABLE (
    id UUID, risk_category_id UUID, category_name TEXT, inherent_rating NUMERIC,
    control_effectiveness NUMERIC, mitigation_factor_applied NUMERIC, residual_rating NUMERIC,
    is_override BOOLEAN, override_reason TEXT, scored_by TEXT, created_at TIMESTAMPTZ
) AS $$
    SELECT s.id, s.risk_category_id, rc.name, s.inherent_rating, s.control_effectiveness,
           s.mitigation_factor_applied, s.residual_rating, s.is_override, s.override_reason, s.scored_by, s.created_at
    FROM assessment_risk_score s
    JOIN risk_category rc ON rc.id = s.risk_category_id
    WHERE s.assessment_id = p_assessment_id;
$$ LANGUAGE sql STABLE;

-- ---- functions/scoring/func_overrideRiskScore.sql ----
-- US-7.2: reason mandatory; residual must stay > 0 even after an override (controls mitigate,
-- they never eliminate - the rule applies to analyst judgment too, not just the formula).
CREATE OR REPLACE FUNCTION func_overrideRiskScore(
    p_assessment_id UUID,
    p_risk_category_id UUID,
    p_new_residual_rating NUMERIC,
    p_reason TEXT,
    p_actor_user_id UUID
) RETURNS UUID AS $$
DECLARE
    v_id UUID;
    v_before JSONB;
BEGIN
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'A reason is required to override a risk score';
    END IF;
    IF p_new_residual_rating <= 0 THEN
        RAISE EXCEPTION 'residual_rating must be greater than zero - controls mitigate risk, they never eliminate it';
    END IF;

    SELECT to_jsonb(s) INTO v_before FROM assessment_risk_score s
        WHERE assessment_id = p_assessment_id AND risk_category_id = p_risk_category_id;

    UPDATE assessment_risk_score
    SET residual_rating = p_new_residual_rating, is_override = true, override_reason = p_reason
    WHERE assessment_id = p_assessment_id AND risk_category_id = p_risk_category_id
    RETURNING id INTO v_id;

    INSERT INTO audit_event (assessment_id, entity_type, entity_id, action, actor_user_id, actor_label, before_value, after_value, reason)
    VALUES (p_assessment_id, 'RiskScore', v_id, 'Overridden', p_actor_user_id, 'human',
            v_before, jsonb_build_object('riskCategoryId', p_risk_category_id, 'residual', p_new_residual_rating), p_reason);

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- ---- functions/scoring/func_upsertScoringConfig.sql ----
-- US-10.1: config change is a new versioned row; rejects any value that would let residual risk
-- reach zero (also enforced by scoring_config's own CHECK - this RAISE gives the friendlier,
-- explicit error message the acceptance criteria calls for).
CREATE OR REPLACE FUNCTION func_upsertScoringConfig(
    p_risk_category_id UUID,
    p_max_mitigation_factor NUMERIC,
    p_reason TEXT,
    p_actor_user_id UUID
) RETURNS UUID AS $$
DECLARE
    v_id UUID := gen_random_uuid();
BEGIN
    IF p_max_mitigation_factor >= 1.0 OR p_max_mitigation_factor < 0 THEN
        RAISE EXCEPTION 'max_mitigation_factor must be in [0, 1.0) - a value of 1.0 or more would let residual risk reach zero';
    END IF;
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'A reason is required to change a scoring configuration';
    END IF;

    UPDATE scoring_config SET is_active = false WHERE risk_category_id = p_risk_category_id AND is_active = true;

    INSERT INTO scoring_config (id, risk_category_id, max_mitigation_factor, created_by_user_id, reason)
    VALUES (v_id, p_risk_category_id, p_max_mitigation_factor, p_actor_user_id, p_reason);

    INSERT INTO audit_event (entity_type, entity_id, action, actor_user_id, actor_label, after_value, reason)
    VALUES ('ScoringConfig', v_id, 'ConfigChanged', p_actor_user_id, 'human',
            jsonb_build_object('riskCategoryId', p_risk_category_id, 'maxMitigationFactor', p_max_mitigation_factor), p_reason);

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- ---- functions/users/func_getAllUsers.sql ----
-- Dev-only convenience: lets the frontend simulate "acting as" a given seeded user/role since
-- there's no real Auth0 login wired up yet (see DevBypassAuthHandler.cs). Not meant to survive
-- real auth being wired in - a real deployment derives identity from the access token, not a
-- public user-listing endpoint.
CREATE OR REPLACE FUNCTION func_getAllUsers()
RETURNS TABLE (id UUID, display_name TEXT, email TEXT, role TEXT) AS $$
    SELECT id, display_name, email, role
    FROM app_user
    WHERE is_active = true
    ORDER BY role, display_name;
$$ LANGUAGE sql STABLE;

-- ============================== seed ==================================================

-- ---- seed/seed_dev_users.sql ----
-- Synthetic users for local dev (100% synthetic per the hackathon's own constraint - never
-- connects to a real system or real identities).
INSERT INTO app_user (auth0_subject, email, display_name, role) VALUES
    ('seed|product-owner-1', 'po1@example.bank', 'Priya Owens', 'ProductOwner'),
    ('seed|analyst-1', 'analyst1@example.bank', 'Amara Chen', 'Analyst'),
    ('seed|analyst-2', 'analyst2@example.bank', 'Sam Okafor', 'Analyst'),
    ('seed|committee-1', 'committee1@example.bank', 'Jordan Blake', 'CommitteeMember'),
    ('seed|committee-2', 'committee2@example.bank', 'Riley Voss', 'CommitteeMember'),
    ('seed|admin-1', 'admin1@example.bank', 'Taylor Finch', 'Admin')
ON CONFLICT (auth0_subject) DO NOTHING;

-- ---- seed/seed_ffiec_framework.sql ----
-- The FFIEC BSA/AML risk framework from CLAUDE.md - run after seed_dev_users.sql (scoring_config
-- below references the seeded Admin user).

INSERT INTO risk_framework (id, name, citation_source)
VALUES ('11111111-1111-1111-1111-111111111111', 'FFIEC BSA/AML Examination Manual', 'FFIEC BSA/AML Examination Manual (bsaaml.ffiec.gov)')
ON CONFLICT (name) DO NOTHING;

INSERT INTO risk_category (id, risk_framework_id, code, name, citation_section) VALUES
    ('22222222-2222-2222-2222-222222222221', '11111111-1111-1111-1111-111111111111', 'PRODUCTS_SERVICES', 'Products & Services', 'FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Products and Services'),
    ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', 'CUSTOMERS_ENTITIES', 'Customers & Entities', 'FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Customers'),
    ('22222222-2222-2222-2222-222222222223', '11111111-1111-1111-1111-111111111111', 'GEOGRAPHIC_LOCATIONS', 'Geographic Locations', 'FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Geographic Locations'),
    ('22222222-2222-2222-2222-222222222224', '11111111-1111-1111-1111-111111111111', 'DELIVERY_CHANNELS', 'Delivery Channels', 'FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Products and Services (Delivery Channels)')
ON CONFLICT (risk_framework_id, code) DO NOTHING;

INSERT INTO risk_subfactor (risk_category_id, name) VALUES
    ('22222222-2222-2222-2222-222222222221', 'ACH'),
    ('22222222-2222-2222-2222-222222222221', 'Wire transfers'),
    ('22222222-2222-2222-2222-222222222221', 'Foreign exchange'),
    ('22222222-2222-2222-2222-222222222221', 'Trade finance'),
    ('22222222-2222-2222-2222-222222222221', 'Private banking'),
    ('22222222-2222-2222-2222-222222222221', 'Prepaid access'),
    ('22222222-2222-2222-2222-222222222221', 'Correspondent banking'),
    ('22222222-2222-2222-2222-222222222222', 'Cash-intensive businesses'),
    ('22222222-2222-2222-2222-222222222222', 'Politically exposed persons (PEPs)'),
    ('22222222-2222-2222-2222-222222222222', 'Non-resident aliens'),
    ('22222222-2222-2222-2222-222222222222', 'Money services businesses (MSBs)'),
    ('22222222-2222-2222-2222-222222222222', 'NGOs / charities'),
    ('22222222-2222-2222-2222-222222222222', 'Shell companies'),
    ('22222222-2222-2222-2222-222222222222', 'Beneficial ownership complexity'),
    ('22222222-2222-2222-2222-222222222223', 'FATF high-risk / monitored jurisdictions'),
    ('22222222-2222-2222-2222-222222222223', 'OFAC sanctioned countries'),
    ('22222222-2222-2222-2222-222222222223', 'Domestic HIFCAs'),
    ('22222222-2222-2222-2222-222222222224', 'In-person / branch'),
    ('22222222-2222-2222-2222-222222222224', 'Online / non-face-to-face'),
    ('22222222-2222-2222-2222-222222222224', 'Third-party agents'),
    ('22222222-2222-2222-2222-222222222224', 'Correspondent relationships')
ON CONFLICT (risk_category_id, name) DO NOTHING;

-- CLAUDE.md's change-type -> primary/secondary category mapping table.
INSERT INTO change_request_type_category_map (change_type, risk_category_id, weight) VALUES
    ('Product', '22222222-2222-2222-2222-222222222221', 'Primary'),
    ('Product', '22222222-2222-2222-2222-222222222222', 'Secondary'),
    ('Feature', '22222222-2222-2222-2222-222222222221', 'Primary'),
    ('Process', '22222222-2222-2222-2222-222222222224', 'Primary'),
    ('Vendor', '22222222-2222-2222-2222-222222222222', 'Primary'),
    ('Vendor', '22222222-2222-2222-2222-222222222224', 'Secondary'),
    ('Geography', '22222222-2222-2222-2222-222222222223', 'Primary'),
    ('Geography', '22222222-2222-2222-2222-222222222221', 'Secondary'),
    ('CustomerSegment', '22222222-2222-2222-2222-222222222222', 'Primary')
ON CONFLICT (change_type, risk_category_id) DO NOTHING;

-- Initial scoring configuration per category (US-10.1). Conservative MVP default; change later via
-- func_upsertScoringConfig (every change is itself a versioned, audited row - see schema/010_scoring.sql).
-- Run once against an empty scoring_config table - re-running this file will add a second (now
-- active) version per category, which is harmless but not idempotent by design (config changes are
-- meant to accumulate as history, not be deduplicated).
INSERT INTO scoring_config (risk_category_id, max_mitigation_factor, created_by_user_id, reason)
SELECT rc.id, 0.85, u.id, 'Initial MVP default - see docs/architecture/architecture-mapping.md'
FROM risk_category rc, app_user u
WHERE u.auth0_subject = 'seed|admin-1'
  AND NOT EXISTS (SELECT 1 FROM scoring_config sc WHERE sc.risk_category_id = rc.id);

-- ---- seed/seed_policy_corpus.sql ----
-- A small, real-excerpt policy corpus so Epic 3's full-text search (func_searchPolicyChunks) has
-- genuine hits to return. Excerpts are short paraphrases of publicly published FFIEC BSA/AML
-- Examination Manual guidance (bsaaml.ffiec.gov), chunked per risk category - not the verbatim
-- manual text, and not a substitute for it in a real deployment. Run after seed_ffiec_framework.sql.

INSERT INTO policy_document (id, risk_framework_id, title, source_url, effective_date, version_label)
VALUES ('33333333-3333-3333-3333-333333333331', '11111111-1111-1111-1111-111111111111',
        'FFIEC BSA/AML Examination Manual', 'https://bsaaml.ffiec.gov', '2014-01-01', '2014 ed.')
ON CONFLICT (id) DO NOTHING;

INSERT INTO policy_chunk (policy_document_id, risk_category_id, section_ref, chunk_text) VALUES
    ('33333333-3333-3333-3333-333333333331', '22222222-2222-2222-2222-222222222221',
     'Risks Associated with Money Laundering and Terrorist Financing - Products and Services',
     'Certain products and services are inherently vulnerable to money laundering because they involve rapid movement of funds or limited face-to-face contact, including electronic funds transfers, correspondent banking, private banking, trade finance, and prepaid access products. Examiners assess whether a bank has identified, measured, and mitigated the risks these offerings present before launch.'),
    ('33333333-3333-3333-3333-333333333331', '22222222-2222-2222-2222-222222222221',
     'Risks Associated with Money Laundering and Terrorist Financing - Correspondent Banking',
     'Correspondent accounts, particularly those for foreign financial institutions, can expose a bank to the risks of the respondent''s own customer base and the adequacy of its AML controls. Enhanced due diligence is expected for correspondent relationships involving higher-risk jurisdictions or nested account arrangements.'),
    ('33333333-3333-3333-3333-333333333331', '22222222-2222-2222-2222-222222222222',
     'Risks Associated with Money Laundering and Terrorist Financing - Customers',
     'Certain categories of customers and entities pose elevated money laundering risk, including cash-intensive businesses, money services businesses, non-resident aliens, politically exposed persons, and non-governmental organizations operating in higher-risk sectors. A risk-based customer due diligence program should scale scrutiny to the customer''s risk profile.'),
    ('33333333-3333-3333-3333-333333333331', '22222222-2222-2222-2222-222222222222',
     'Risks Associated with Money Laundering and Terrorist Financing - Beneficial Ownership',
     'Legal entity customers with complex or opaque ownership structures, including shell companies, can be used to obscure the identity of beneficial owners. Banks are expected to identify and verify beneficial owners holding a defined ownership threshold as part of customer due diligence.'),
    ('33333333-3333-3333-3333-333333333331', '22222222-2222-2222-2222-222222222223',
     'Risks Associated with Money Laundering and Terrorist Financing - Geographic Locations',
     'Geographic risk considers a bank''s exposure to jurisdictions identified by FATF as having strategic AML/CFT deficiencies, countries subject to OFAC sanctions programs, and domestic High Intensity Financial Crime Areas (HIFCAs). Products, customers, and transactions tied to these locations warrant additional scrutiny.'),
    ('33333333-3333-3333-3333-333333333331', '22222222-2222-2222-2222-222222222224',
     'Risks Associated with Money Laundering and Terrorist Financing - Delivery Channels',
     'Non-face-to-face account opening and transaction channels, including online and mobile banking, and reliance on third-party agents or correspondent relationships to deliver products, reduce a bank''s ability to verify customer identity and intent directly, and should be factored into the overall risk assessment of a proposed change.')
;

-- ---- seed/seed_workflow_rules.sql ----
-- Default workflow rules (Epic 10, US-10.2). Run after seed_dev_users.sql.
--
-- CommitteeQuorum: how many committee votes CommitteeService.cs waits for before resolving a
-- decision (Epic 8). This is the MVP's answer to CLAUDE.md's open question ("majority vote,
-- unanimous consent, or chair's call?") - see docs/architecture/architecture-mapping.md for the
-- documented resolution rule this quorum feeds into.
INSERT INTO workflow_rule (rule_key, rule_value, created_by_user_id, reason)
SELECT 'CommitteeQuorum', '{"quorum": 2}'::jsonb, u.id, 'Initial MVP default - see docs/architecture/architecture-mapping.md'
FROM app_user u
WHERE u.auth0_subject = 'seed|admin-1'
  AND NOT EXISTS (SELECT 1 FROM workflow_rule WHERE rule_key = 'CommitteeQuorum');

COMMIT;
