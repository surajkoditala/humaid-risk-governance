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
