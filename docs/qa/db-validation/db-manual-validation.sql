-- Manual read-only data validation - Risk Assessment Workbench
-- Same SQL the Playwright db suite ran (tests/e2e/specs/db/01-data-integrity.db.spec.ts).
-- Run:  docker exec -it risk-governance-postgres psql -U postgres -d risk_governance_db
-- then paste one block at a time, or run the whole file with \i (see docs/qa/db-validation/README.md).

SET default_transaction_read_only = on;   -- safety: any write in this session now fails
SHOW transaction_read_only;               -- must print: on
\x auto

-- =====================================================================
-- TC-DB-000
-- =====================================================================

\echo 'TC-DB-000: read only flag'
-- local Docker result: null row(s)
SHOW transaction_read_only;

\echo 'TC-DB-000: login role'
-- local Docker result: 1 row(s)
SELECT current_user AS usr, current_database() AS db, version() AS version, (SELECT rolsuper
  FROM pg_roles
  WHERE rolname = current_user) AS superuser, has_table_privilege(current_user, 'public.audit_event', 'INSERT') AS can_insert_audit, has_table_privilege(current_user, 'public.change_request', 'UPDATE') AS can_update_cr;

-- =====================================================================
-- TC-DB-001
-- =====================================================================

\echo 'TC-DB-001: tables'
-- local Docker result: 26 row(s)
SELECT CASE WHEN table_schema = 'public' THEN table_name ELSE table_schema || '.' || table_name END AS t
  FROM information_schema.tables
  WHERE table_schema IN ('public','mock_systems') AND table_type = 'BASE TABLE';

-- =====================================================================
-- TC-DB-002
-- =====================================================================

\echo 'TC-DB-002: audit trigger'
-- local Docker result: 1 row(s)
SELECT t.tgname, t.tgenabled, pg_get_triggerdef(t.oid) AS def, p.prosrc
  FROM pg_trigger t
  JOIN pg_class c ON c.oid = t.tgrelid
  JOIN pg_proc p ON p.oid = t.tgfoid
  WHERE c.relname = 'audit_event' AND NOT t.tgisinternal;

\echo 'TC-DB-002: audit mutators'
-- local Docker result: 0 row(s)
SELECT proname
  FROM pg_proc
  WHERE proname ~* '(update|delete).*audit|audit.*(update|delete)' AND proname <> 'fn_block_audit_event_mutation';

-- =====================================================================
-- TC-DB-003
-- =====================================================================

\echo 'TC-DB-003: frameworks'
-- local Docker result: 1 row(s)
SELECT name, citation_source
  FROM risk_framework;

\echo 'TC-DB-003: categories subfactors'
-- local Docker result: 4 row(s)
SELECT c.code, c.name, c.citation_section, count(s.id) AS subfactors
  FROM risk_category c
  LEFT JOIN risk_subfactor s ON s.risk_category_id = c.id
  GROUP BY c.id
  ORDER BY c.code;

-- =====================================================================
-- TC-DB-004
-- =====================================================================

\echo 'TC-DB-004: type map'
-- local Docker result: 9 row(s)
SELECT m.change_type, c.code, m.weight
  FROM change_request_type_category_map m
  JOIN risk_category c ON c.id = m.risk_category_id
  ORDER BY 1, 3, 2;

-- =====================================================================
-- TC-DB-005
-- =====================================================================

\echo 'TC-DB-005: roles'
-- local Docker result: 4 row(s)
SELECT role, count(*) AS n
  FROM app_user
  GROUP BY role
  ORDER BY role;

\echo 'TC-DB-005: duplicates'
-- local Docker result: 1 row(s)
SELECT (SELECT count(*)
  FROM (SELECT lower(email)
  FROM app_user
  GROUP BY 1
  HAVING count(*) > 1) x) AS dup_email, (SELECT count(*)
  FROM (SELECT auth0_subject
  FROM app_user
  WHERE auth0_subject <> ''
  GROUP BY 1
  HAVING count(*) > 1) y) AS dup_subject;

\echo 'TC-DB-005: non example emails'
-- local Docker result: 0 row(s)
SELECT email
  FROM app_user
  WHERE email !~* '@example\.(bank|com|org|net)$';

-- =====================================================================
-- TC-DB-006
-- =====================================================================

\echo 'TC-DB-006: foreign keys'
-- local Docker result: 42 row(s)
SELECT conrelid::regclass::text AS tbl, conname, convalidated
  FROM pg_constraint
  WHERE contype = 'f' AND connamespace = 'public'::regnamespace
  ORDER BY 1;

-- =====================================================================
-- TC-DB-010
-- =====================================================================

\echo 'TC-DB-010: score scan'
-- local Docker result: 1 row(s)
SELECT count(*) AS total,
  count(*) FILTER (WHERE residual_rating <= 0) AS nonpositive,
  count(*) FILTER (WHERE mitigation_factor_applied >= 1) AS mf_ge_1,
  count(*) FILTER (WHERE NOT is_override AND abs(residual_rating - (inherent_rating - control_effectiveness * mitigation_factor_applied)) > 0.01) AS formula_mismatch, min(residual_rating) AS min_residual
  FROM assessment_risk_score;

-- =====================================================================
-- TC-DB-011
-- =====================================================================

\echo 'TC-DB-011: override scan'
-- local Docker result: 1 row(s)
SELECT count(*) AS overrides,
  count(*) FILTER (WHERE coalesce(trim(override_reason), '') = '') AS no_reason,
  count(*) FILTER (WHERE scored_by <> 'Analyst') AS not_analyst,
  count(*) FILTER (WHERE created_by_user_id IS NULL) AS no_actor,
  count(*) FILTER (WHERE NOT EXISTS (SELECT 1
  FROM audit_event e
  WHERE e.entity_id = s.id AND e.action = 'Overridden' AND e.before_value IS NOT NULL)) AS no_before_value
  FROM assessment_risk_score s
  WHERE is_override;

-- =====================================================================
-- TC-DB-012
-- =====================================================================

\echo 'TC-DB-012: scoring config'
-- local Docker result: 4 row(s)
SELECT c.code,
  count(*) FILTER (WHERE sc.is_active) AS active, count(*) AS versions, max(sc.max_mitigation_factor) FILTER (WHERE sc.is_active) AS active_mf,
  count(*) FILTER (WHERE coalesce(trim(sc.reason),'') = '') AS no_reason
  FROM risk_category c
  LEFT JOIN scoring_config sc ON sc.risk_category_id = c.id
  GROUP BY c.code
  ORDER BY 1;

-- =====================================================================
-- TC-DB-013
-- =====================================================================

\echo 'TC-DB-013: config pinning'
-- local Docker result: 1 row(s)
SELECT count(*) AS assessments,
  count(*) FILTER (WHERE scoring_config_version_id IS NULL) AS unpinned
  FROM assessment;

\echo 'TC-DB-013: scores vs pinned'
-- local Docker result: 1 row(s)
SELECT count(*) AS mismatched
  FROM assessment_risk_score s
  JOIN assessment a ON a.id = s.assessment_id
  JOIN scoring_config sc ON sc.id = a.scoring_config_version_id
  WHERE NOT s.is_override AND sc.risk_category_id = s.risk_category_id AND sc.max_mitigation_factor <> s.mitigation_factor_applied;

-- =====================================================================
-- TC-DB-014
-- =====================================================================

\echo 'TC-DB-014: status consistency'
-- local Docker result: 1 row(s)
SELECT count(*) FILTER (WHERE cr.status IN ('InAssessment','PendingCommittee','Decisioned') AND a.id IS NULL) AS progressed_without_assessment,
  count(*) FILTER (WHERE cr.status = 'PendingCommittee' AND a.status <> 'Finalized') AS pending_not_finalized,
  count(*) FILTER (WHERE cr.status = 'Decisioned' AND d.id IS NULL) AS decisioned_without_decision,
  count(*) FILTER (WHERE cr.status <> 'Decisioned' AND d.id IS NOT NULL) AS decision_but_not_decisioned,
  count(*) FILTER (WHERE a.status = 'Finalized' AND (a.finalized_by_user_id IS NULL OR a.finalized_at IS NULL)) AS finalized_anonymous, count(*) AS requests
  FROM change_request cr
  LEFT JOIN assessment a ON a.change_request_id = cr.id
  LEFT JOIN committee_decision d ON d.assessment_id = a.id;

-- =====================================================================
-- TC-DB-015
-- =====================================================================

\echo 'TC-DB-015: finalized gate scan'
-- local Docker result: 12 row(s)
SELECT cr.request_number, cr.title, (SELECT count(*)
  FROM assessment_category_mapping m
  WHERE m.assessment_id = a.id AND m.is_active) AS cats, (SELECT count(*)
  FROM assessment_narrative_section ns
  WHERE ns.assessment_id = a.id AND ns.status = 'AiDrafted') AS ai_drafted, (SELECT count(*)
  FROM assessment_category_mapping m
  WHERE m.assessment_id = a.id AND m.is_active AND NOT EXISTS (SELECT 1
  FROM assessment_risk_score s
  WHERE s.assessment_id = a.id AND s.risk_category_id = m.risk_category_id)) AS unscored, (SELECT count(*)
  FROM assessment_category_mapping m
  WHERE m.assessment_id = a.id AND m.is_active AND NOT EXISTS (SELECT 1
  FROM assessment_policy_reliance r
  WHERE r.assessment_id = a.id AND (r.risk_category_id = m.risk_category_id OR r.risk_category_id IS NULL))) AS no_policy
  FROM assessment a
  JOIN change_request cr ON cr.id = a.change_request_id
  WHERE a.status = 'Finalized';

-- =====================================================================
-- TC-DB-016
-- =====================================================================

\echo 'TC-DB-016: vote scan'
-- local Docker result: 1 row(s)
SELECT count(*) AS votes,
  count(*) FILTER (WHERE u.role <> 'CommitteeMember') AS non_member_votes,
  count(*) FILTER (WHERE v.vote = 'ApproveWithConditions' AND coalesce(trim(v.conditions_text),'') = '') AS blank_conditions,
  count(*) FILTER (WHERE v.vote IN ('Reject','Defer') AND coalesce(trim(v.rationale),'') = '') AS blank_rationale
  FROM committee_vote v
  JOIN app_user u ON u.id = v.committee_member_user_id;

\echo 'TC-DB-016: non member voters'
-- local Docker result: 0 row(s)
SELECT cr.request_number, u.display_name, u.role, v.vote
  FROM committee_vote v
  JOIN app_user u ON u.id = v.committee_member_user_id
  JOIN assessment a ON a.id = v.assessment_id
  JOIN change_request cr ON cr.id = a.change_request_id
  WHERE u.role <> 'CommitteeMember';

\echo 'TC-DB-016: decisions vs quorum'
-- local Docker result: 1 row(s)
SELECT count(*) AS decisions,
  count(*) FILTER (WHERE (SELECT count(*)
  FROM committee_vote v
  JOIN app_user u ON u.id = v.committee_member_user_id
  WHERE v.assessment_id = d.assessment_id AND u.role = 'CommitteeMember') < coalesce((SELECT (rule_value->>'quorum')::int
  FROM workflow_rule
  WHERE rule_key = 'CommitteeQuorum' AND is_active LIMIT 1), 2)) AS below_quorum
  FROM committee_decision d;

-- =====================================================================
-- TC-DB-017
-- =====================================================================

\echo 'TC-DB-017: attachment scan'
-- local Docker result: 1 row(s)
SELECT count(*) AS files, max(version_number) AS max_version,
  count(*) FILTER (WHERE superseded_by_attachment_id IS NOT NULL) AS superseded,
  count(*) FILTER (WHERE (content_type = 'application/pdf' AND file_name !~* '\.pdf$') OR (content_type LIKE '%wordprocessingml%' AND file_name !~* '\.docx$') OR (content_type LIKE '%spreadsheetml%' AND file_name !~* '\.xlsx$')) AS ext_mismatch,
  count(*) FILTER (WHERE coalesce(trim(extracted_text),'') = '') AS no_text
  FROM change_request_attachment;

\echo 'TC-DB-017: extension mismatches'
-- local Docker result: 0 row(s)
SELECT file_name, content_type
  FROM change_request_attachment
  WHERE (content_type = 'application/pdf' AND file_name !~* '\.pdf$') OR (content_type LIKE '%wordprocessingml%' AND file_name !~* '\.docx$') OR (content_type LIKE '%spreadsheetml%' AND file_name !~* '\.xlsx$');

-- =====================================================================
-- TC-DB-018
-- =====================================================================

\echo 'TC-DB-018: request quality'
-- local Docker result: 1 row(s)
SELECT count(*) AS requests,
  count(*) FILTER (WHERE trim(title) = '') AS blank_title,
  count(*) FILTER (WHERE trim(description) = '') AS blank_description,
  count(*) FILTER (WHERE length(title) > 500) AS overlong_title,
  count(*) FILTER (WHERE request_number !~ '^CR-\d{4}-\d{5}$') AS bad_number, max(length(title)) AS max_title_len
  FROM change_request;

\echo 'TC-DB-018: number gaps'
-- local Docker result: 1 row(s)
SELECT count(*) AS gaps
  FROM (SELECT substring(request_number, 9)::int AS nbr, lag(substring(request_number, 9)::int) OVER (PARTITION BY substring(request_number, 4, 4)
  ORDER BY substring(request_number, 9)::int) AS prev
  FROM change_request
  WHERE request_number ~ '^CR-\d{4}-\d{5}$') x
  WHERE prev IS NOT NULL AND nbr <> prev + 1;

-- =====================================================================
-- TC-DB-019
-- =====================================================================

\echo 'TC-DB-019: reliance unique key'
-- local Docker result: 1 row(s)
SELECT pg_get_constraintdef(oid) AS def
  FROM pg_constraint
  WHERE conrelid = 'assessment_policy_reliance'::regclass AND contype = 'u';

-- =====================================================================
-- TC-DB-020
-- =====================================================================

\echo 'TC-DB-020: audit scan'
-- local Docker result: 1 row(s)
SELECT count(*) AS events,
  count(*) FILTER (WHERE actor_label = 'human' AND actor_user_id IS NULL) AS human_no_user,
  count(*) FILTER (WHERE actor_label NOT IN ('human','system/AI')) AS bad_label,
  count(*) FILTER (WHERE action ~* '(overrid|edit|correct|configchang|removed|added)' AND coalesce(trim(reason),'') = '') AS change_no_reason,
  count(*) FILTER (WHERE created_at > now() + interval '5 minutes') AS future,
  count(*) FILTER (WHERE change_request_id IS NULL AND assessment_id IS NULL AND entity_type NOT IN ('ScoringConfig','WorkflowRule')) AS unanchored
  FROM audit_event;

\echo 'TC-DB-020: changes without reason'
-- local Docker result: 0 row(s)
SELECT entity_type, action, count(*) AS n
  FROM audit_event
  WHERE action ~* '(overrid|edit|correct|configchang|removed|added)' AND coalesce(trim(reason),'') = ''
  GROUP BY 1, 2
  ORDER BY 3 DESC;

-- =====================================================================
-- TC-DB-021
-- =====================================================================

\echo 'TC-DB-021: audit coverage'
-- local Docker result: 9 row(s)
SELECT 'change_request' AS entity,
  count(*) FILTER (WHERE NOT EXISTS (SELECT 1
  FROM audit_event e
  WHERE e.change_request_id = x.id AND e.entity_type = 'ChangeRequest')) AS missing, count(*) AS total
  FROM change_request x
  UNION ALL SELECT 'attachment',
  count(*) FILTER (WHERE NOT EXISTS (SELECT 1
  FROM audit_event e
  WHERE e.entity_id = x.id)), count(*)
  FROM change_request_attachment x
  UNION ALL SELECT 'category_mapping',
  count(*) FILTER (WHERE NOT EXISTS (SELECT 1
  FROM audit_event e
  WHERE e.assessment_id = x.assessment_id AND e.entity_type = 'CategoryMapping')), count(*)
  FROM assessment_category_mapping x
  UNION ALL SELECT 'narrative',
  count(*) FILTER (WHERE NOT EXISTS (SELECT 1
  FROM audit_event e
  WHERE e.entity_id = x.id)), count(*)
  FROM assessment_narrative_section x
  UNION ALL SELECT 'risk_score',
  count(*) FILTER (WHERE NOT EXISTS (SELECT 1
  FROM audit_event e
  WHERE e.entity_id = x.id)), count(*)
  FROM assessment_risk_score x
  UNION ALL SELECT 'committee_vote',
  count(*) FILTER (WHERE NOT EXISTS (SELECT 1
  FROM audit_event e
  WHERE e.entity_id = x.id)), count(*)
  FROM committee_vote x
  UNION ALL SELECT 'committee_decision',
  count(*) FILTER (WHERE NOT EXISTS (SELECT 1
  FROM audit_event e
  WHERE e.entity_id = x.id OR (e.assessment_id = x.assessment_id AND e.entity_type = 'CommitteeDecision'))), count(*)
  FROM committee_decision x
  UNION ALL SELECT 'scoring_config (post-seed)',
  count(*) FILTER (WHERE NOT EXISTS (SELECT 1
  FROM audit_event e
  WHERE e.entity_id = x.id)), count(*)
  FROM scoring_config x
  WHERE x.created_at > (SELECT min(created_at) + interval '10 minutes'
  FROM app_user)
  UNION ALL SELECT 'workflow_rule (post-seed)',
  count(*) FILTER (WHERE NOT EXISTS (SELECT 1
  FROM audit_event e
  WHERE e.entity_id = x.id)), count(*)
  FROM workflow_rule x
  WHERE x.created_at > (SELECT min(created_at) + interval '10 minutes'
  FROM app_user);

-- =====================================================================
-- TC-DB-022
-- =====================================================================

\echo 'TC-DB-022: revotes'
-- local Docker result: 0 row(s)
SELECT cr.request_number, u.display_name, v.vote AS stored_vote, count(e.id) AS audit_events, string_agg(coalesce(e.after_value->>'vote', '?'), ' -> '
  ORDER BY e.created_at) AS history
  FROM committee_vote v
  JOIN app_user u ON u.id = v.committee_member_user_id
  JOIN assessment a ON a.id = v.assessment_id
  JOIN change_request cr ON cr.id = a.change_request_id
  LEFT JOIN audit_event e ON e.entity_id = v.id AND e.entity_type = 'CommitteeVote'
  GROUP BY cr.request_number, u.display_name, v.vote
  HAVING count(e.id) > 1;

-- =====================================================================
-- TC-DB-030
-- =====================================================================

\echo 'TC-DB-030: snapshot resolution'
-- local Docker result: 1 row(s)
SELECT count(*) AS snapshots,
  count(*) FILTER (WHERE mock_customer_id IS NOT NULL AND NOT EXISTS (SELECT 1
  FROM mock_systems.crm_customer c
  WHERE c.id = x.mock_customer_id)) AS dangling_customer,
  count(*) FILTER (WHERE mock_product_id IS NOT NULL AND NOT EXISTS (SELECT 1
  FROM mock_systems.core_banking_product p
  WHERE p.id = x.mock_product_id)) AS dangling_product,
  count(*) FILTER (WHERE mock_vendor_id IS NOT NULL AND NOT EXISTS (SELECT 1
  FROM mock_systems.vendor_registry v
  WHERE v.id = x.mock_vendor_id)) AS dangling_vendor,
  count(*) FILTER (WHERE (mock_customer_id IS NOT NULL AND customer_risk_context IS NULL) OR (mock_product_id IS NOT NULL AND product_risk_context IS NULL) OR (mock_vendor_id IS NOT NULL AND vendor_risk_context IS NULL)) AS missing_context
  FROM change_request_external_snapshot x;

-- =====================================================================
-- TC-DB-031
-- =====================================================================

\echo 'TC-DB-031: feedback loop'
-- local Docker result: 0 row(s)
SELECT cr.request_number, d.resolution, CASE WHEN x.mock_product_id IS NOT NULL THEN (SELECT (p.go_live_flag IS NOT NULL AND p.risk_rating IS NOT NULL)
  FROM mock_systems.core_banking_product p
  WHERE p.id = x.mock_product_id) WHEN x.mock_vendor_id IS NOT NULL THEN (SELECT v.updated_risk_rating IS NOT NULL
  FROM mock_systems.vendor_registry v
  WHERE v.id = x.mock_vendor_id) WHEN x.mock_customer_id IS NOT NULL THEN (SELECT c.risk_flag IS NOT NULL
  FROM mock_systems.crm_customer c
  WHERE c.id = x.mock_customer_id) END AS written_back
  FROM committee_decision d
  JOIN assessment a ON a.id = d.assessment_id
  JOIN change_request cr ON cr.id = a.change_request_id
  JOIN change_request_external_snapshot x ON x.change_request_id = cr.id
  WHERE coalesce(x.mock_product_id, x.mock_vendor_id, x.mock_customer_id) IS NOT NULL;

-- =====================================================================
-- TC-DB-032
-- =====================================================================

\echo 'TC-DB-032: pii scan'
-- local Docker result: 0 row(s)
WITH t AS ( SELECT 'change_request' AS src, request_number AS ref, title || ' ' || description || ' ' || type_specific_fields::text AS txt
  FROM change_request
  UNION ALL SELECT 'extracted_field', field_key, coalesce(field_value,'') || ' ' || coalesce(source_excerpt,'')
  FROM extracted_field
  UNION ALL SELECT 'narrative', id::text, narrative_text
  FROM assessment_narrative_section
  UNION ALL SELECT 'committee_vote', id::text, coalesce(conditions_text,'') || ' ' || coalesce(rationale,'')
  FROM committee_vote
  UNION ALL SELECT 'crm_customer', id::text, customer_name
  FROM mock_systems.crm_customer) SELECT src, ref, CASE WHEN txt ~ '\m\d{3}-\d{2}-\d{4}\M' THEN 'SSN' WHEN txt ~ '\m(?:\d[ -]?){15,16}\M' THEN 'card-number' WHEN txt ~ '\m[A-Z]{2}\d{2}[A-Z0-9]{11,30}\M' THEN 'IBAN' ELSE 'e-mail' END AS kind
  FROM t
  WHERE txt ~ '\m\d{3}-\d{2}-\d{4}\M' OR txt ~ '\m(?:\d[ -]?){15,16}\M' OR txt ~ '\m[A-Z]{2}\d{2}[A-Z0-9]{11,30}\M' OR txt ~* '[a-z0-9._%+-]+@(?!example\.)[a-z0-9.-]+\.[a-z]{2,}';

-- =====================================================================
-- TC-DB-033
-- =====================================================================

\echo 'TC-DB-033: coverage'
-- local Docker result: 4 row(s)
SELECT c.code, (SELECT count(*)
  FROM control k
  WHERE k.risk_category_id = c.id) AS controls, (SELECT count(*)
  FROM policy_chunk p
  WHERE p.risk_category_id = c.id) AS passages
  FROM risk_category c
  ORDER BY 1;

\echo 'TC-DB-033: policy documents'
-- local Docker result: 1 row(s)
SELECT count(*) AS docs,
  count(*) FILTER (WHERE source_url !~ '^https?://' OR coalesce(trim(version_label),'') = '') AS incomplete, (SELECT count(*)
  FROM policy_chunk) AS chunks
  FROM policy_document;

-- =====================================================================
-- TC-DB-034
-- =====================================================================

\echo 'TC-DB-034: workflow rules'
-- local Docker result: 1 row(s)
SELECT rule_key,
  count(*) FILTER (WHERE is_active) AS active, count(*) AS versions, max(rule_value::text) FILTER (WHERE is_active) AS value,
  count(*) FILTER (WHERE coalesce(trim(reason),'') = '') AS no_reason
  FROM workflow_rule
  GROUP BY 1;

-- =====================================================================
-- TC-DB-035
-- =====================================================================

\echo 'TC-DB-035: qa footprint'
-- local Docker result: 1 row(s)
SELECT count(*) AS requests,
  count(*) FILTER (WHERE status = 'PendingCommittee') AS still_in_queue, (SELECT count(*)
  FROM change_request) AS all_requests
  FROM change_request
  WHERE title LIKE '[QA-E2E%';
