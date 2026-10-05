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
     'Non-face-to-face account opening and transaction channels, including online and mobile banking, and reliance on third-party agents or correspondent relationships to deliver products, reduce a bank''s ability to verify customer identity and intent directly, and should be factored into the overall risk assessment of a proposed change.'),

    -- DEF-032: the corpus was too thin - a broad query returned only 5 passages and "wire
    -- transfer" / "high-risk jurisdiction" returned nothing at all, despite both being core
    -- FFIEC/FATF topics. These additional excerpts broaden coverage across all four categories.
    ('33333333-3333-3333-3333-333333333331', '22222222-2222-2222-2222-222222222221',
     'Risks Associated with Money Laundering and Terrorist Financing - Wire Transfers',
     'Wire transfers permit the rapid movement of funds between banks domestically and internationally and are a common vehicle for laundering illicit proceeds. A bank should retain complete originator and beneficiary information on wire transfers, screen transfers against sanctions lists, and apply enhanced scrutiny to wire activity that is inconsistent with a customer''s stated business or expected transaction profile.'),
    ('33333333-3333-3333-3333-333333333331', '22222222-2222-2222-2222-222222222221',
     'Risks Associated with Money Laundering and Terrorist Financing - Automated Clearing House',
     'Automated Clearing House (ACH) transactions, particularly third-party payment processor relationships, can be used to originate a high volume of low-dollar transactions that individually evade scrutiny. A bank offering ACH origination services should understand the nature of the underlying payments being processed on its behalf.'),
    ('33333333-3333-3333-3333-333333333331', '22222222-2222-2222-2222-222222222221',
     'Risks Associated with Money Laundering and Terrorist Financing - Private Banking',
     'Private banking relationships often involve higher-net-worth customers, complex account structures, and a greater expectation of confidentiality, all of which can be exploited to obscure the source of funds. Enhanced due diligence, including identification of the source of wealth, is expected for private banking customers.'),
    ('33333333-3333-3333-3333-333333333331', '22222222-2222-2222-2222-222222222222',
     'Risks Associated with Money Laundering and Terrorist Financing - Sanctions Screening of Customers',
     'A bank''s customer due diligence program should include screening of new and existing customers against OFAC''s Specially Designated Nationals list and other applicable sanctions lists at onboarding and on an ongoing basis, with a documented process for resolving potential matches before an account is opened or a transaction is processed.'),
    ('33333333-3333-3333-3333-333333333331', '22222222-2222-2222-2222-222222222222',
     'Risks Associated with Money Laundering and Terrorist Financing - Prepaid Access Customers',
     'Prepaid access products sold or distributed to customers, including general-purpose reloadable cards, can be used to structure funds below reporting thresholds or move value with limited identity verification. A bank should apply customer due diligence proportionate to the funding, reload, and redemption features offered.'),
    ('33333333-3333-3333-3333-333333333331', '22222222-2222-2222-2222-222222222223',
     'Risks Associated with Money Laundering and Terrorist Financing - High-Risk Jurisdictions',
     'A bank should identify customers, products, and transactions connected to a high-risk jurisdiction, including a country identified by FATF as having strategic AML/CFT deficiencies, before establishing or continuing the relationship, and apply enhanced due diligence commensurate with the jurisdiction''s risk profile.'),
    ('33333333-3333-3333-3333-333333333331', '22222222-2222-2222-2222-222222222223',
     'Risks Associated with Money Laundering and Terrorist Financing - OFAC Sanctioned Countries',
     'Transactions or relationships involving a country subject to a comprehensive OFAC sanctions program are generally prohibited absent a specific license, and a bank should have controls in place to identify and block such activity before it settles.'),
    ('33333333-3333-3333-3333-333333333331', '22222222-2222-2222-2222-222222222223',
     'Risks Associated with Money Laundering and Terrorist Financing - Domestic High Intensity Financial Crime Areas',
     'Domestic High Intensity Financial Crime Areas (HIFCAs) are geographic regions designated for concentrated law enforcement attention because of elevated money laundering activity; a bank with a significant footprint in a HIFCA should factor that geographic concentration into its overall risk assessment.'),
    ('33333333-3333-3333-3333-333333333331', '22222222-2222-2222-2222-222222222224',
     'Risks Associated with Money Laundering and Terrorist Financing - Third-Party Agents',
     'A bank that relies on third-party agents to open accounts or process transactions on its behalf should conduct due diligence on the agent, monitor the agent''s activity, and periodically audit the agent''s compliance with the bank''s AML program, since the delivery channel itself does not reduce the bank''s own compliance obligations.')
ON CONFLICT (policy_document_id, section_ref) DO NOTHING;
