-- ==================================================================================
-- deploy_all.sql - GENERATED FILE. Do not edit directly.
-- Regenerate with ./generate_deploy_all.sh after changing schema.sql, functions/, or seed.sql.
--
-- One-shot setup for Humaid.RiskGovernance.MockSystems: creates the 'mock_systems' schema,
-- its 3 tables, every stored function the service calls, and seeds synthetic dev data -
-- against the SAME Postgres instance/database the Workbench uses (different schema, not a
-- separate database - see README.md). Run once. Not idempotent by design, same as the
-- Workbench's own deploy_all.sql.
--
-- Usage (against the same Docker Postgres the Workbench already uses):
--   psql -U postgres -h localhost -p 5433 -d risk_governance_db -v ON_ERROR_STOP=1 -f deploy_all.sql
-- ==================================================================================

BEGIN;

-- ============================== schema ==============================================

-- ---- schema.sql ----
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

-- ============================== functions ============================================

-- ---- functions/customers/func_getCustomerById.sql ----
CREATE OR REPLACE FUNCTION func_getCustomerById(p_id UUID)
RETURNS TABLE (
    id UUID, customer_name TEXT, customer_type TEXT, customer_geography TEXT,
    segment_classification TEXT, kyc_status TEXT, risk_flag TEXT
) AS $$
    SELECT id, customer_name, customer_type, customer_geography, segment_classification, kyc_status, risk_flag
    FROM mock_systems.crm_customer
    WHERE id = p_id;
$$ LANGUAGE sql;

-- ---- functions/customers/func_listCustomers.sql ----
CREATE OR REPLACE FUNCTION func_listCustomers()
RETURNS TABLE (
    id UUID, customer_name TEXT, customer_type TEXT, customer_geography TEXT,
    segment_classification TEXT, kyc_status TEXT, risk_flag TEXT
) AS $$
    SELECT id, customer_name, customer_type, customer_geography, segment_classification, kyc_status, risk_flag
    FROM mock_systems.crm_customer
    ORDER BY customer_name;
$$ LANGUAGE sql;

-- ---- functions/customers/func_updateCustomerRiskFlag.sql ----
-- Inbound side of the feedback loop (Phase 3 Step 5). Returns the updated row's id, or no rows if
-- p_id didn't match anything - the caller (Program.cs) maps that to 404, same as before this was
-- moved into a function.
CREATE OR REPLACE FUNCTION func_updateCustomerRiskFlag(p_id UUID, p_risk_flag TEXT)
RETURNS TABLE (id UUID) AS $$
    UPDATE mock_systems.crm_customer
    SET risk_flag = p_risk_flag
    WHERE id = p_id
    RETURNING id;
$$ LANGUAGE sql;

-- ---- functions/products/func_getProductById.sql ----
CREATE OR REPLACE FUNCTION func_getProductById(p_id UUID)
RETURNS TABLE (
    id UUID, product_name TEXT, product_type TEXT, features_json JSONB,
    product_geography TEXT, launch_change_type TEXT, go_live_flag BOOLEAN, risk_rating TEXT
) AS $$
    SELECT id, product_name, product_type, features_json, product_geography, launch_change_type, go_live_flag, risk_rating
    FROM mock_systems.core_banking_product
    WHERE id = p_id;
$$ LANGUAGE sql;

-- ---- functions/products/func_listProducts.sql ----
CREATE OR REPLACE FUNCTION func_listProducts()
RETURNS TABLE (
    id UUID, product_name TEXT, product_type TEXT, features_json JSONB,
    product_geography TEXT, launch_change_type TEXT, go_live_flag BOOLEAN, risk_rating TEXT
) AS $$
    SELECT id, product_name, product_type, features_json, product_geography, launch_change_type, go_live_flag, risk_rating
    FROM mock_systems.core_banking_product
    ORDER BY product_name;
$$ LANGUAGE sql;

-- ---- functions/products/func_updateProductRiskRating.sql ----
-- Inbound side of the feedback loop (Phase 3 Step 5) - go-live flag + risk rating pushed back
-- from a committee decision.
CREATE OR REPLACE FUNCTION func_updateProductRiskRating(p_id UUID, p_go_live BOOLEAN, p_risk_rating TEXT)
RETURNS TABLE (id UUID) AS $$
    UPDATE mock_systems.core_banking_product
    SET go_live_flag = p_go_live, risk_rating = p_risk_rating
    WHERE id = p_id
    RETURNING id;
$$ LANGUAGE sql;

-- ---- functions/vendors/func_getVendorById.sql ----
CREATE OR REPLACE FUNCTION func_getVendorById(p_id UUID)
RETURNS TABLE (
    id UUID, vendor_name TEXT, vendor_risk_rating TEXT, vendor_jurisdiction TEXT,
    data_access_scope TEXT, certification_status TEXT, updated_risk_rating TEXT
) AS $$
    SELECT id, vendor_name, vendor_risk_rating, vendor_jurisdiction, data_access_scope, certification_status, updated_risk_rating
    FROM mock_systems.vendor_registry
    WHERE id = p_id;
$$ LANGUAGE sql;

-- ---- functions/vendors/func_listVendors.sql ----
CREATE OR REPLACE FUNCTION func_listVendors()
RETURNS TABLE (
    id UUID, vendor_name TEXT, vendor_risk_rating TEXT, vendor_jurisdiction TEXT,
    data_access_scope TEXT, certification_status TEXT, updated_risk_rating TEXT
) AS $$
    SELECT id, vendor_name, vendor_risk_rating, vendor_jurisdiction, data_access_scope, certification_status, updated_risk_rating
    FROM mock_systems.vendor_registry
    ORDER BY vendor_name;
$$ LANGUAGE sql;

-- ---- functions/vendors/func_updateVendorRiskRating.sql ----
-- Inbound side of the feedback loop (Phase 3 Step 5) - updated vendor risk rating pushed back
-- from a committee decision.
CREATE OR REPLACE FUNCTION func_updateVendorRiskRating(p_id UUID, p_updated_risk_rating TEXT)
RETURNS TABLE (id UUID) AS $$
    UPDATE mock_systems.vendor_registry
    SET updated_risk_rating = p_updated_risk_rating
    WHERE id = p_id
    RETURNING id;
$$ LANGUAGE sql;

-- ============================== seed ==================================================

-- ---- seed.sql ----
-- Synthetic data only - see docs/architecture/architecture-mapping.md's "Mock External Systems"
-- section and ai/data-generation/README.md for how this was assembled. Row 1 in each table is the
-- hand-authored "golden path" triplet (same customer/product/vendor story, used for the reliable
-- demo lifecycle); the rest are additional variety plus two deliberate edge cases the architect's
-- ecosystem doc calls for: a customer/product pairing with no clean FFIEC category mapping, and a
-- vendor missing certification.

INSERT INTO mock_systems.crm_customer (id, customer_name, customer_type, customer_geography, segment_classification, kyc_status, risk_flag) VALUES
    ('a1111111-0000-0000-0000-000000000001', 'Meridian Textiles Ltd', 'Corporate', 'Bangladesh', 'Commercial', 'Verified', NULL), -- golden path
    ('a1111111-0000-0000-0000-000000000002', 'Riya Kapoor', 'Individual', 'United States', 'Retail', 'Verified', NULL), -- edge case: no clean framework mapping (plain domestic retail)
    ('a1111111-0000-0000-0000-000000000003', 'Al-Sharq Money Exchange', 'MSB', 'United Arab Emirates', 'Commercial', 'Flagged', NULL),
    ('a1111111-0000-0000-0000-000000000004', 'Global Relief Foundation', 'NGO', 'Kenya', 'Commercial', 'Pending', NULL),
    ('a1111111-0000-0000-0000-000000000005', 'Fenwick & Cole Boutique Advisors', 'SmallBusiness', 'United Kingdom', 'PrivateBanking', 'Verified', NULL),
    ('a1111111-0000-0000-0000-000000000006', 'Novak Family Trust', 'Individual', 'Switzerland', 'PrivateBanking', 'Verified', NULL)
ON CONFLICT (id) DO NOTHING;

INSERT INTO mock_systems.core_banking_product (id, product_name, product_type, features_json, product_geography, launch_change_type, go_live_flag, risk_rating) VALUES
    ('b2222222-0000-0000-0000-000000000001', 'Cross-Border Wire Transfer Plus', 'WireTransfer', '{"dailyLimitUsd": 500000, "channels": ["online","branch"]}', 'Bangladesh', 'New', NULL, NULL), -- golden path
    ('b2222222-0000-0000-0000-000000000002', 'Mobile App UI Refresh', 'ProcessChange', '{"scope": "UI only, no new data flows"}', 'United States', 'ProcessChange', NULL, NULL), -- edge case: no clean framework mapping
    ('b2222222-0000-0000-0000-000000000003', 'Prepaid Travel Card', 'PrepaidAccess', '{"maxLoadUsd": 10000, "reloadable": true}', 'United Arab Emirates', 'New', NULL, NULL),
    ('b2222222-0000-0000-0000-000000000004', 'Correspondent Settlement Account', 'CorrespondentBanking', '{"nestedAccountsAllowed": false}', 'Kenya', 'New', NULL, NULL),
    ('b2222222-0000-0000-0000-000000000005', 'Private Banking Trade Finance Line', 'TradeFinance', '{"facilityLimitUsd": 2000000}', 'Switzerland', 'FeatureAdd', NULL, NULL)
ON CONFLICT (id) DO NOTHING;

INSERT INTO mock_systems.vendor_registry (id, vendor_name, vendor_risk_rating, vendor_jurisdiction, data_access_scope, certification_status, updated_risk_rating) VALUES
    ('c3333333-0000-0000-0000-000000000001', 'Global KYC Solutions Inc', 'Medium', 'Singapore', 'Customer PII for identity verification', 'Certified', NULL), -- golden path
    ('c3333333-0000-0000-0000-000000000002', 'QuickPay Processing LLC', 'High', 'Cayman Islands', 'Full transaction data, card PANs', 'None', NULL), -- edge case: missing certification
    ('c3333333-0000-0000-0000-000000000003', 'Northbridge Document Services', 'Low', 'Canada', 'Scanned onboarding documents only', 'Certified', NULL),
    ('c3333333-0000-0000-0000-000000000004', 'Vantage AML Screening Ltd', 'Medium', 'United Kingdom', 'Sanctions/PEP screening queries', 'Pending', NULL)
ON CONFLICT (id) DO NOTHING;

COMMIT;
