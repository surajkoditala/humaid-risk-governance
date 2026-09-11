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
