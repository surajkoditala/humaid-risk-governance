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
