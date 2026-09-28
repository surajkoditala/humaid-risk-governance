-- DEF-013: the controls library was entirely empty (0 rows for every category), so
-- Scoring/Controls/{riskCategoryId} always returned [] and the UI could never credit a control -
-- US-7.1 AC3 ("trace which specific controls were credited") had nothing to trace. Run after
-- seed_ffiec_framework.sql (references its risk_category ids).
INSERT INTO control (risk_category_id, name, description) VALUES
    ('22222222-2222-2222-2222-222222222221', 'Wire transfer transaction monitoring', 'Automated rule-based monitoring of outbound/inbound wire transfers for structuring and high-risk counterparties.'),
    ('22222222-2222-2222-2222-222222222221', 'Trade finance dual review', 'Second-reviewer sign-off on trade finance instruments above a defined value threshold.'),
    ('22222222-2222-2222-2222-222222222221', 'Prepaid access load limits', 'System-enforced daily/monthly load and reload limits on prepaid access products.'),
    ('22222222-2222-2222-2222-222222222221', 'Correspondent banking due diligence', 'Periodic AML risk-rating review of correspondent banking relationships.'),

    ('22222222-2222-2222-2222-222222222222', 'Enhanced due diligence for PEPs', 'Mandatory enhanced due diligence and senior-management sign-off before onboarding a politically exposed person.'),
    ('22222222-2222-2222-2222-222222222222', 'Beneficial ownership verification', 'Verification of beneficial ownership to the 25% threshold for legal-entity customers at onboarding.'),
    ('22222222-2222-2222-2222-222222222222', 'Cash-intensive business monitoring thresholds', 'Tiered transaction-monitoring thresholds calibrated to a cash-intensive business''s expected activity.'),
    ('22222222-2222-2222-2222-222222222222', 'MSB registration verification', 'Verification of FinCEN MSB registration status prior to account opening.'),

    ('22222222-2222-2222-2222-222222222223', 'OFAC sanctions screening', 'Real-time screening of parties and transactions against OFAC and other sanctions lists.'),
    ('22222222-2222-2222-2222-222222222223', 'FATF high-risk jurisdiction escalation', 'Automatic escalation to FCRM review for activity involving a FATF high-risk or monitored jurisdiction.'),
    ('22222222-2222-2222-2222-222222222223', 'Geographic risk scoring model', 'Country-level risk scoring feeding into customer and transaction risk ratings.'),

    ('22222222-2222-2222-2222-222222222224', 'Non-face-to-face identity verification', 'Documentary and non-documentary identity verification for online/non-face-to-face account opening.'),
    ('22222222-2222-2222-2222-222222222224', 'Third-party agent oversight program', 'Periodic audit and monitoring of third-party agents acting on the bank''s behalf.'),
    ('22222222-2222-2222-2222-222222222224', 'Correspondent relationship due diligence', 'Due diligence on the delivery-channel risk of correspondent banking relationships.')
ON CONFLICT (risk_category_id, name) DO NOTHING;
