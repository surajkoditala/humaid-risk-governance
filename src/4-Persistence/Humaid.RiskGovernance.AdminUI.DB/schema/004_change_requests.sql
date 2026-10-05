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
