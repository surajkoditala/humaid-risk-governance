-- The FFIEC BSA/AML risk framework from CLAUDE.md - run after seed_dev_users.sql (scoring_config
-- below references the seeded Admin user).

INSERT INTO risk_framework (id, name, citation_source)
VALUES ('11111111-1111-1111-1111-111111111111', 'FFIEC BSA/AML Examination Manual', 'FFIEC BSA/AML Examination Manual (bsaaml.ffiec.gov)')
ON CONFLICT (name) DO NOTHING;

INSERT INTO risk_category (id, risk_framework_id, code, name, citation_section) VALUES
    ('22222222-2222-2222-2222-222222222221', '11111111-1111-1111-1111-111111111111', 'PRODUCTS_SERVICES', 'Products & Services', 'FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Products and Services'),
    ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', 'CUSTOMERS_ENTITIES', 'Customers & Entities', 'FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Customers'),
    ('22222222-2222-2222-2222-222222222223', '11111111-1111-1111-1111-111111111111', 'GEOGRAPHIC_LOCATIONS', 'Geographic Locations', 'FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Geographic Locations'),
    ('22222222-2222-2222-2222-222222222224', '11111111-1111-1111-1111-111111111111', 'DELIVERY_CHANNELS', 'Delivery Channels', 'FFIEC BSA/AML Manual - Risks Associated with Money Laundering and Terrorist Financing: Products and Services (Delivery Channels)')
ON CONFLICT (risk_framework_id, code) DO NOTHING;

INSERT INTO risk_subfactor (risk_category_id, name) VALUES
    ('22222222-2222-2222-2222-222222222221', 'ACH'),
    ('22222222-2222-2222-2222-222222222221', 'Wire transfers'),
    ('22222222-2222-2222-2222-222222222221', 'Foreign exchange'),
    ('22222222-2222-2222-2222-222222222221', 'Trade finance'),
    ('22222222-2222-2222-2222-222222222221', 'Private banking'),
    ('22222222-2222-2222-2222-222222222221', 'Prepaid access'),
    ('22222222-2222-2222-2222-222222222221', 'Correspondent banking'),
    ('22222222-2222-2222-2222-222222222222', 'Cash-intensive businesses'),
    ('22222222-2222-2222-2222-222222222222', 'Politically exposed persons (PEPs)'),
    ('22222222-2222-2222-2222-222222222222', 'Non-resident aliens'),
    ('22222222-2222-2222-2222-222222222222', 'Money services businesses (MSBs)'),
    ('22222222-2222-2222-2222-222222222222', 'NGOs / charities'),
    ('22222222-2222-2222-2222-222222222222', 'Shell companies'),
    ('22222222-2222-2222-2222-222222222222', 'Beneficial ownership complexity'),
    ('22222222-2222-2222-2222-222222222223', 'FATF high-risk / monitored jurisdictions'),
    ('22222222-2222-2222-2222-222222222223', 'OFAC sanctioned countries'),
    ('22222222-2222-2222-2222-222222222223', 'Domestic HIFCAs'),
    ('22222222-2222-2222-2222-222222222224', 'In-person / branch'),
    ('22222222-2222-2222-2222-222222222224', 'Online / non-face-to-face'),
    ('22222222-2222-2222-2222-222222222224', 'Third-party agents'),
    ('22222222-2222-2222-2222-222222222224', 'Correspondent relationships')
ON CONFLICT (risk_category_id, name) DO NOTHING;

-- CLAUDE.md's change-type -> primary/secondary category mapping table.
INSERT INTO change_request_type_category_map (change_type, risk_category_id, weight) VALUES
    ('Product', '22222222-2222-2222-2222-222222222221', 'Primary'),
    ('Product', '22222222-2222-2222-2222-222222222222', 'Secondary'),
    ('Feature', '22222222-2222-2222-2222-222222222221', 'Primary'),
    ('Process', '22222222-2222-2222-2222-222222222224', 'Primary'),
    ('Vendor', '22222222-2222-2222-2222-222222222222', 'Primary'),
    ('Vendor', '22222222-2222-2222-2222-222222222224', 'Secondary'),
    ('Geography', '22222222-2222-2222-2222-222222222223', 'Primary'),
    ('Geography', '22222222-2222-2222-2222-222222222221', 'Secondary'),
    ('CustomerSegment', '22222222-2222-2222-2222-222222222222', 'Primary')
ON CONFLICT (change_type, risk_category_id) DO NOTHING;

-- Initial scoring configuration per category (US-10.1). Conservative MVP default; change later via
-- func_upsertScoringConfig (every change is itself a versioned, audited row - see schema/010_scoring.sql).
-- Run once against an empty scoring_config table - re-running this file will add a second (now
-- active) version per category, which is harmless but not idempotent by design (config changes are
-- meant to accumulate as history, not be deduplicated).
INSERT INTO scoring_config (risk_category_id, max_mitigation_factor, created_by_user_id, reason)
SELECT rc.id, 0.85, u.id, 'Initial MVP default - see docs/architecture/architecture-mapping.md'
FROM risk_category rc, app_user u
WHERE u.auth0_subject = 'seed|admin-1'
  AND NOT EXISTS (SELECT 1 FROM scoring_config sc WHERE sc.risk_category_id = rc.id);
