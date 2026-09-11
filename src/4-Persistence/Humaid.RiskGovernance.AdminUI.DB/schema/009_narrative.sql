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
