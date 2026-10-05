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
