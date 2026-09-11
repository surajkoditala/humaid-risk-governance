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
