-- A small, real-excerpt policy corpus so Epic 3's full-text search (func_searchPolicyChunks) has
-- genuine hits to return. Excerpts are short paraphrases of publicly published FFIEC BSA/AML
-- Examination Manual guidance (bsaaml.ffiec.gov), chunked per risk category - not the verbatim
-- manual text, and not a substitute for it in a real deployment. Run after seed_ffiec_framework.sql.

INSERT INTO policy_document (id, risk_framework_id, title, source_url, effective_date, version_label)
VALUES ('33333333-3333-3333-3333-333333333331', '11111111-1111-1111-1111-111111111111',
        'FFIEC BSA/AML Examination Manual', 'https://bsaaml.ffiec.gov', '2014-01-01', '2014 ed.')
ON CONFLICT (id) DO NOTHING;

INSERT INTO policy_chunk (policy_document_id, risk_category_id, section_ref, chunk_text) VALUES
    ('33333333-3333-3333-3333-333333333331', '22222222-2222-2222-2222-222222222221',
     'Risks Associated with Money Laundering and Terrorist Financing - Products and Services',
     'Certain products and services are inherently vulnerable to money laundering because they involve rapid movement of funds or limited face-to-face contact, including electronic funds transfers, correspondent banking, private banking, trade finance, and prepaid access products. Examiners assess whether a bank has identified, measured, and mitigated the risks these offerings present before launch.'),
    ('33333333-3333-3333-3333-333333333331', '22222222-2222-2222-2222-222222222221',
     'Risks Associated with Money Laundering and Terrorist Financing - Correspondent Banking',
     'Correspondent accounts, particularly those for foreign financial institutions, can expose a bank to the risks of the respondent''s own customer base and the adequacy of its AML controls. Enhanced due diligence is expected for correspondent relationships involving higher-risk jurisdictions or nested account arrangements.'),
    ('33333333-3333-3333-3333-333333333331', '22222222-2222-2222-2222-222222222222',
     'Risks Associated with Money Laundering and Terrorist Financing - Customers',
     'Certain categories of customers and entities pose elevated money laundering risk, including cash-intensive businesses, money services businesses, non-resident aliens, politically exposed persons, and non-governmental organizations operating in higher-risk sectors. A risk-based customer due diligence program should scale scrutiny to the customer''s risk profile.'),
    ('33333333-3333-3333-3333-333333333331', '22222222-2222-2222-2222-222222222222',
     'Risks Associated with Money Laundering and Terrorist Financing - Beneficial Ownership',
     'Legal entity customers with complex or opaque ownership structures, including shell companies, can be used to obscure the identity of beneficial owners. Banks are expected to identify and verify beneficial owners holding a defined ownership threshold as part of customer due diligence.'),
    ('33333333-3333-3333-3333-333333333331', '22222222-2222-2222-2222-222222222223',
     'Risks Associated with Money Laundering and Terrorist Financing - Geographic Locations',
     'Geographic risk considers a bank''s exposure to jurisdictions identified by FATF as having strategic AML/CFT deficiencies, countries subject to OFAC sanctions programs, and domestic High Intensity Financial Crime Areas (HIFCAs). Products, customers, and transactions tied to these locations warrant additional scrutiny.'),
    ('33333333-3333-3333-3333-333333333331', '22222222-2222-2222-2222-222222222224',
     'Risks Associated with Money Laundering and Terrorist Financing - Delivery Channels',
     'Non-face-to-face account opening and transaction channels, including online and mobile banking, and reliance on third-party agents or correspondent relationships to deliver products, reduce a bank''s ability to verify customer identity and intent directly, and should be factored into the overall risk assessment of a proposed change.')
;
