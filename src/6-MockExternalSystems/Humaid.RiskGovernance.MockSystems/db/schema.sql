-- Mock External Systems - deliberately its own Postgres SCHEMA namespace (not just tables in
-- 'public'), even though this runs against the same Docker Postgres instance as the Workbench for
-- local simplicity. This is the DB-level expression of "not part of the Workbench": the Workbench's
-- own connection string/user only ever needs SELECT/UPDATE on these tables through this service's
-- HTTP API, never a direct connection into this schema - see docs/architecture/architecture-mapping.md.

CREATE SCHEMA IF NOT EXISTS mock_systems;

CREATE TABLE mock_systems.crm_customer (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_name TEXT NOT NULL,
    customer_type TEXT NOT NULL CHECK (customer_type IN ('Individual','SmallBusiness','Corporate','MSB','NGO')),
    customer_geography TEXT NOT NULL,
    segment_classification TEXT NOT NULL CHECK (segment_classification IN ('Retail','PrivateBanking','Commercial')),
    kyc_status TEXT NOT NULL CHECK (kyc_status IN ('Verified','Pending','Flagged')),
    risk_flag TEXT, -- written back by the Workbench's feedback loop (Phase 3 Step 5) - null until a decision pushes one
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE mock_systems.core_banking_product (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_name TEXT NOT NULL,
    product_type TEXT NOT NULL, -- e.g. WireTransfer, PrepaidCard, TradeFinance, CorrespondentBanking
    features_json JSONB NOT NULL DEFAULT '{}'::jsonb, -- limits, channel, etc.
    product_geography TEXT NOT NULL,
    launch_change_type TEXT NOT NULL CHECK (launch_change_type IN ('New','FeatureAdd','ProcessChange')),
    go_live_flag BOOLEAN, -- written back by the feedback loop
    risk_rating TEXT, -- written back by the feedback loop
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE mock_systems.vendor_registry (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vendor_name TEXT NOT NULL,
    vendor_risk_rating TEXT NOT NULL CHECK (vendor_risk_rating IN ('Low','Medium','High')), -- as originally on file
    vendor_jurisdiction TEXT NOT NULL,
    data_access_scope TEXT NOT NULL,
    certification_status TEXT NOT NULL CHECK (certification_status IN ('Certified','Pending','None')),
    updated_risk_rating TEXT, -- written back by the feedback loop
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
