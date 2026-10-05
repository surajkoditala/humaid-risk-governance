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
