import { expect, test } from '@playwright/test'
import type { Client } from 'pg'
import { actual, defect, tc } from '../../lib/harness'
import { connect, dbUrl, describeTarget, q } from '../../lib/db'

test.skip(!dbUrl(), 'DB_URL / .env.db not provided - read-only DB data tests not run')

let db: Client
test.beforeAll(async () => {
  db = await connect()
})
test.afterAll(async () => {
  await db?.end()
})

const n = (x: any) => Number(x)

test.describe('Safety gate', () => {
  test('TC-DB-000 Session is read-only before any check runs', async () => {
    tc({ id: 'TC-DB-000', story: 'QA safety', type: 'Data', priority: 'P1', steps: ['Connect with default_transaction_read_only=on', 'SHOW transaction_read_only', 'Inspect the login role privileges'], expected: 'transaction_read_only = on. Ideally the login is a dedicated read-only role (no INSERT/UPDATE/DELETE grants)' })
    const [ro] = await q(db, 'read-only flag', 'SHOW transaction_read_only')
    const [who] = await q(db, 'login role', `SELECT current_user AS usr, current_database() AS db, version() AS version,
      (SELECT rolsuper FROM pg_roles WHERE rolname = current_user) AS superuser,
      has_table_privilege(current_user, 'public.audit_event', 'INSERT') AS can_insert_audit,
      has_table_privilege(current_user, 'public.change_request', 'UPDATE') AS can_update_cr`)
    actual(`target ${describeTarget(dbUrl()!)}; transaction_read_only=${ro.transaction_read_only}; role ${who.usr} superuser=${who.superuser} canInsertAudit=${who.can_insert_audit} canUpdateCR=${who.can_update_cr}`)
    expect(ro.transaction_read_only).toBe('on')
    expect.soft(who.can_update_cr, 'a dedicated read-only role is recommended for QA access').toBe(false)
  })
})

test.describe('Schema & seed data', () => {
  test('TC-DB-001 All expected tables exist (Workbench + mock_systems)', async () => {
    const expected = ['risk_framework', 'risk_category', 'risk_subfactor', 'change_request_type_category_map', 'app_user', 'change_request', 'change_request_attachment', 'change_request_clarification', 'change_request_external_snapshot', 'assessment', 'assessment_category_mapping', 'policy_document', 'policy_chunk', 'assessment_policy_reliance', 'extracted_field', 'assessment_narrative_section', 'control', 'scoring_config', 'assessment_risk_score', 'committee_vote', 'committee_decision', 'workflow_rule', 'audit_event', 'mock_systems.crm_customer', 'mock_systems.core_banking_product', 'mock_systems.vendor_registry']
    tc({ id: 'TC-DB-001', story: 'Architecture', type: 'Data', priority: 'P1', steps: ['Query information_schema.tables for public + mock_systems'], expected: `All ${expected.length} tables from schema/*.sql and the mock_systems deploy script exist` })
    const rows = await q(db, 'tables', `SELECT CASE WHEN table_schema = 'public' THEN table_name ELSE table_schema || '.' || table_name END AS t FROM information_schema.tables WHERE table_schema IN ('public','mock_systems') AND table_type = 'BASE TABLE'`)
    const have = new Set(rows.map((r) => r.t))
    const missing = expected.filter((t) => !have.has(t))
    actual(`${have.size} tables present; missing: ${missing.join(', ') || 'none'}`)
    expect(missing).toEqual([])
  })

  test('TC-DB-002 Audit table is append-only at the data layer (trigger present and enabled)', async () => {
    tc({ id: 'TC-DB-002', story: 'US-9.2', type: 'Data', priority: 'P1', steps: ['Read pg_trigger for audit_event', 'Read the trigger function body', 'Check no UPDATE/DELETE audit functions exist'], expected: 'BEFORE UPDATE OR DELETE trigger enabled, raising an exception; no func_update*/delete* audit routine' })
    const trg = await q(db, 'audit trigger', `SELECT t.tgname, t.tgenabled, pg_get_triggerdef(t.oid) AS def, p.prosrc FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_proc p ON p.oid = t.tgfoid WHERE c.relname = 'audit_event' AND NOT t.tgisinternal`)
    const fns = await q(db, 'audit mutators', `SELECT proname FROM pg_proc WHERE proname ~* '(update|delete).*audit|audit.*(update|delete)' AND proname <> 'fn_block_audit_event_mutation'`)
    const t = trg[0]
    actual(t ? `${t.tgname} enabled=${t.tgenabled} (${t.def.replace(/\s+/g, ' ')}); raises: ${/RAISE EXCEPTION/i.test(t.prosrc)}; mutating audit functions: ${fns.map((f) => f.proname).join(', ') || 'none'}` : 'no trigger on audit_event')
    expect(t, 'trigger exists').toBeTruthy()
    expect(t.tgenabled).toBe('O')
    expect(t.def).toMatch(/BEFORE (UPDATE OR DELETE|DELETE OR UPDATE)/)
    expect(t.prosrc).toMatch(/RAISE EXCEPTION/i)
    expect(fns).toEqual([])
  })

  test('TC-DB-003 Risk framework seed is the citable FFIEC framework', async () => {
    tc({ id: 'TC-DB-003', story: 'US-2.1', type: 'Data', priority: 'P1', steps: ['Read risk_framework, risk_category, risk_subfactor'], expected: 'One FFIEC framework with a citation source; exactly the 4 FFIEC categories, each with a citation section and at least 3 sub-factors' })
    const fw = await q(db, 'frameworks', 'SELECT name, citation_source FROM risk_framework')
    const cats = await q(db, 'categories + subfactors', `SELECT c.code, c.name, c.citation_section, count(s.id) AS subfactors FROM risk_category c LEFT JOIN risk_subfactor s ON s.risk_category_id = c.id GROUP BY c.id ORDER BY c.code`)
    actual(`frameworks: ${fw.map((f) => `${f.name} (${f.citation_source})`).join('; ')}; categories: ${cats.map((c) => `${c.code}=${c.subfactors} sub-factors`).join(', ')}`)
    expect(fw.some((f) => /FFIEC/.test(f.name + f.citation_source))).toBeTruthy()
    expect(cats.map((c) => c.code).sort()).toEqual(['CUSTOMERS_ENTITIES', 'DELIVERY_CHANNELS', 'GEOGRAPHIC_LOCATIONS', 'PRODUCTS_SERVICES'])
    for (const c of cats) {
      expect(c.citation_section).toMatch(/FFIEC/)
      expect.soft(n(c.subfactors), `${c.code} sub-factors`).toBeGreaterThanOrEqual(3)
    }
  })

  test('TC-DB-004 Change-type -> category map matches the documented mapping', async () => {
    const want: Record<string, string[]> = {
      Product: ['PRODUCTS_SERVICES', 'CUSTOMERS_ENTITIES'],
      Feature: ['PRODUCTS_SERVICES'],
      Process: ['DELIVERY_CHANNELS'],
      Vendor: ['CUSTOMERS_ENTITIES', 'DELIVERY_CHANNELS'],
      Geography: ['GEOGRAPHIC_LOCATIONS', 'PRODUCTS_SERVICES'],
      CustomerSegment: ['CUSTOMERS_ENTITIES'],
    }
    tc({ id: 'TC-DB-004', story: 'US-2.1 / CLAUDE.md', type: 'Data', priority: 'P2', steps: ['Read change_request_type_category_map joined to risk_category'], expected: 'Every change type has its documented categories mapped (Vendor -> Customers & Entities + Delivery Channels, etc.)' })
    const rows = await q(db, 'type map', `SELECT m.change_type, c.code, m.weight FROM change_request_type_category_map m JOIN risk_category c ON c.id = m.risk_category_id ORDER BY 1, 3, 2`)
    const got: Record<string, string[]> = {}
    for (const r of rows) (got[r.change_type] ||= []).push(`${r.code}:${r.weight}`)
    const gaps = Object.entries(want).flatMap(([t, cs]) => cs.filter((c) => !(got[t] || []).some((g) => g.startsWith(c + ':'))).map((c) => `${t} missing ${c}`))
    actual(`${Object.entries(got).map(([t, cs]) => `${t}: ${cs.join(', ')}`).join(' | ')}; gaps: ${gaps.join(', ') || 'none'}`)
    expect(gaps).toEqual([])
  })

  test('TC-DB-005 Seeded users: all roles present, identities unique, synthetic e-mails', async () => {
    tc({ id: 'TC-DB-005', story: 'Roles / synthetic data', type: 'Data', priority: 'P2', steps: ['Group app_user by role', 'Check auth0_subject uniqueness', 'Check e-mail domains'], expected: 'All 4 roles present; no duplicate subjects/e-mails; e-mails on reserved example domains only' })
    const roles = await q(db, 'roles', 'SELECT role, count(*) AS n FROM app_user GROUP BY role ORDER BY role')
    const [dup] = await q(db, 'duplicates', `SELECT (SELECT count(*) FROM (SELECT lower(email) FROM app_user GROUP BY 1 HAVING count(*) > 1) x) AS dup_email, (SELECT count(*) FROM (SELECT auth0_subject FROM app_user WHERE auth0_subject <> '' GROUP BY 1 HAVING count(*) > 1) y) AS dup_subject`)
    const nonSynthetic = await q(db, 'non-example emails', `SELECT email FROM app_user WHERE email !~* '@example\\.(bank|com|org|net)$'`)
    actual(`roles: ${roles.map((r) => `${r.role}=${r.n}`).join(', ')}; duplicate e-mails ${dup.dup_email}, subjects ${dup.dup_subject}; non-example e-mails: ${nonSynthetic.length}`)
    expect(roles.map((r) => r.role).sort()).toEqual(['Admin', 'Analyst', 'CommitteeMember', 'ProductOwner'])
    expect(n(dup.dup_email) + n(dup.dup_subject)).toBe(0)
    expect(nonSynthetic).toEqual([])
  })

  test('TC-DB-006 Referential integrity: all foreign keys exist and are validated', async () => {
    tc({ id: 'TC-DB-006', story: 'Data integrity', type: 'Data', priority: 'P1', steps: ['List FK constraints from pg_constraint', 'Check convalidated'], expected: 'Every FK declared in schema/*.sql is present and VALIDATED (no NOT VALID constraints that could hide orphans)' })
    const fks = await q(db, 'foreign keys', `SELECT conrelid::regclass::text AS tbl, conname, convalidated FROM pg_constraint WHERE contype = 'f' AND connamespace = 'public'::regnamespace ORDER BY 1`)
    const invalid = fks.filter((f) => !f.convalidated)
    actual(`${fks.length} foreign keys; not validated: ${invalid.map((f) => f.conname).join(', ') || 'none'}`)
    expect(fks.length).toBeGreaterThanOrEqual(30)
    expect(invalid).toEqual([])
  })
})

test.describe('Business-rule integrity of stored data', () => {
  test('TC-DB-010 Every stored residual is > 0 and matches the formula', async () => {
    tc({ id: 'TC-DB-010', story: 'US-7.1', type: 'Data', priority: 'P1', steps: ['Scan assessment_risk_score', 'For system-calculated rows recompute inherent - effectiveness x mitigation'], expected: 'No residual <= 0; every non-override row equals the formula (±0.01); every mitigation factor < 1' })
    const [s] = await q(db, 'score scan', `SELECT count(*) AS total, count(*) FILTER (WHERE residual_rating <= 0) AS nonpositive, count(*) FILTER (WHERE mitigation_factor_applied >= 1) AS mf_ge_1,
      count(*) FILTER (WHERE NOT is_override AND abs(residual_rating - (inherent_rating - control_effectiveness * mitigation_factor_applied)) > 0.01) AS formula_mismatch,
      min(residual_rating) AS min_residual FROM assessment_risk_score`)
    actual(`${s.total} scores; residual <= 0: ${s.nonpositive}; mf >= 1: ${s.mf_ge_1}; formula mismatches: ${s.formula_mismatch}; min residual ${s.min_residual}`)
    test.skip(n(s.total) === 0, 'Not applicable - no scores stored in this database')
    expect(n(s.nonpositive)).toBe(0)
    expect(n(s.mf_ge_1)).toBe(0)
    expect(n(s.formula_mismatch)).toBe(0)
  })

  test('TC-DB-011 Overridden scores keep a reason, analyst attribution and the original value', async () => {
    tc({ id: 'TC-DB-011', story: 'US-7.2 / US-6.1', type: 'Data', priority: 'P1', steps: ['Select overridden rows', 'Join the RiskScore "Overridden" audit events'], expected: 'Every override has override_reason, scored_by = Analyst, an actor, and an audit event whose before_value holds the calculated residual' })
    const [s] = await q(db, 'override scan', `SELECT count(*) AS overrides, count(*) FILTER (WHERE coalesce(trim(override_reason), '') = '') AS no_reason, count(*) FILTER (WHERE scored_by <> 'Analyst') AS not_analyst, count(*) FILTER (WHERE created_by_user_id IS NULL) AS no_actor,
      count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM audit_event e WHERE e.entity_id = s.id AND e.action = 'Overridden' AND e.before_value IS NOT NULL)) AS no_before_value
      FROM assessment_risk_score s WHERE is_override`)
    actual(`${s.overrides} overrides; blank reason ${s.no_reason}; scored_by not Analyst ${s.not_analyst}; no actor ${s.no_actor}; no audit before_value ${s.no_before_value}`)
    expect(n(s.no_reason)).toBe(0)
    if (n(s.not_analyst) || n(s.no_actor)) defect('DEF-014')
    expect.soft(n(s.not_analyst), 'scored_by should be Analyst').toBe(0)
    expect.soft(n(s.no_actor), 'override actor recorded').toBe(0)
    expect.soft(n(s.no_before_value), 'original calculated value retained in audit').toBe(0)
  })

  test('TC-DB-012 Scoring configuration: one active version per category, all < 1.0, reasoned', async () => {
    tc({ id: 'TC-DB-012', story: 'US-10.1', type: 'Data', priority: 'P1', steps: ['Group scoring_config by category and is_active', 'Check reason/creator'], expected: 'Exactly one active row per category; every factor in [0,1); every version has a reason and creator (history retained, not overwritten)' })
    const rows = await q(db, 'scoring config', `SELECT c.code, count(*) FILTER (WHERE sc.is_active) AS active, count(*) AS versions, max(sc.max_mitigation_factor) FILTER (WHERE sc.is_active) AS active_mf, count(*) FILTER (WHERE coalesce(trim(sc.reason),'') = '') AS no_reason FROM risk_category c LEFT JOIN scoring_config sc ON sc.risk_category_id = c.id GROUP BY c.code ORDER BY 1`)
    actual(rows.map((r) => `${r.code}: active=${r.active} mf=${r.active_mf} versions=${r.versions} blankReason=${r.no_reason}`).join('; '))
    for (const r of rows) {
      expect(n(r.active), r.code).toBe(1)
      expect(Number(r.active_mf)).toBeLessThan(1)
      expect(n(r.no_reason)).toBe(0)
    }
  })

  test('TC-DB-013 Assessments are pinned to the scoring-config version they started with', async () => {
    tc({ id: 'TC-DB-013', story: 'US-10.1 AC1', type: 'Data', priority: 'P2', steps: ['Count assessments with scoring_config_version_id', 'Compare scores\' mitigation factor with the pinned version'], expected: 'Every assessment carries a pinned config version and its scores used that version' })
    defect('DEF-016')
    const [s] = await q(db, 'config pinning', `SELECT count(*) AS assessments, count(*) FILTER (WHERE scoring_config_version_id IS NULL) AS unpinned FROM assessment`)
    const [m] = await q(db, 'scores vs pinned', `SELECT count(*) AS mismatched FROM assessment_risk_score s JOIN assessment a ON a.id = s.assessment_id JOIN scoring_config sc ON sc.id = a.scoring_config_version_id WHERE NOT s.is_override AND sc.risk_category_id = s.risk_category_id AND sc.max_mitigation_factor <> s.mitigation_factor_applied`)
    actual(`${s.assessments} assessments, ${s.unpinned} without a pinned config version; scores deviating from their pinned version: ${m.mismatched}`)
    expect.soft(n(s.unpinned)).toBe(0)
    expect.soft(n(m.mismatched)).toBe(0)
  })

  test('TC-DB-014 Workflow status is consistent across change request, assessment and decision', async () => {
    tc({ id: 'TC-DB-014', story: 'US-1.3 / US-6.3 / US-8.3', type: 'Data', priority: 'P1', steps: ['Cross-check change_request.status against assessment and committee_decision'], expected: 'Submitted -> no finalized assessment; PendingCommittee -> Finalized assessment, no decision; Decisioned <-> exactly one decision; Finalized -> finalizing analyst + timestamp recorded' })
    const [s] = await q(db, 'status consistency', `SELECT
      count(*) FILTER (WHERE cr.status IN ('InAssessment','PendingCommittee','Decisioned') AND a.id IS NULL) AS progressed_without_assessment,
      count(*) FILTER (WHERE cr.status = 'PendingCommittee' AND a.status <> 'Finalized') AS pending_not_finalized,
      count(*) FILTER (WHERE cr.status = 'Decisioned' AND d.id IS NULL) AS decisioned_without_decision,
      count(*) FILTER (WHERE cr.status <> 'Decisioned' AND d.id IS NOT NULL) AS decision_but_not_decisioned,
      count(*) FILTER (WHERE a.status = 'Finalized' AND (a.finalized_by_user_id IS NULL OR a.finalized_at IS NULL)) AS finalized_anonymous,
      count(*) AS requests
      FROM change_request cr LEFT JOIN assessment a ON a.change_request_id = cr.id LEFT JOIN committee_decision d ON d.assessment_id = a.id`)
    actual(`${s.requests} requests; progressed without assessment ${s.progressed_without_assessment}; pending but not finalized ${s.pending_not_finalized}; decisioned without decision ${s.decisioned_without_decision}; decision but status not Decisioned ${s.decision_but_not_decisioned}; finalized without analyst/timestamp ${s.finalized_anonymous}`)
    for (const k of ['progressed_without_assessment', 'pending_not_finalized', 'decisioned_without_decision', 'decision_but_not_decisioned', 'finalized_anonymous']) expect.soft(n(s[k]), k).toBe(0)
  })

  test('TC-DB-015 No finalized assessment skipped the human review gates', async () => {
    tc({ id: 'TC-DB-015', story: 'US-6.3 / US-5.1 / HITL', type: 'Data', priority: 'P1', steps: ['For each Finalized assessment count active categories, AI-drafted sections, categories without a score and without policy reliance'], expected: 'Zero finalized assessments with no categories, an AI-drafted section, a missing score or missing policy review' })
    defect('DEF-001')
    const rows = await q(db, 'finalized gate scan', `SELECT cr.request_number, cr.title,
      (SELECT count(*) FROM assessment_category_mapping m WHERE m.assessment_id = a.id AND m.is_active) AS cats,
      (SELECT count(*) FROM assessment_narrative_section ns WHERE ns.assessment_id = a.id AND ns.status = 'AiDrafted') AS ai_drafted,
      (SELECT count(*) FROM assessment_category_mapping m WHERE m.assessment_id = a.id AND m.is_active AND NOT EXISTS (SELECT 1 FROM assessment_risk_score s WHERE s.assessment_id = a.id AND s.risk_category_id = m.risk_category_id)) AS unscored,
      (SELECT count(*) FROM assessment_category_mapping m WHERE m.assessment_id = a.id AND m.is_active AND NOT EXISTS (SELECT 1 FROM assessment_policy_reliance r WHERE r.assessment_id = a.id AND (r.risk_category_id = m.risk_category_id OR r.risk_category_id IS NULL))) AS no_policy
      FROM assessment a JOIN change_request cr ON cr.id = a.change_request_id WHERE a.status = 'Finalized'`)
    const bad = rows.filter((r) => n(r.cats) === 0 || n(r.ai_drafted) > 0 || n(r.unscored) > 0 || n(r.no_policy) > 0)
    actual(`${rows.length} finalized assessments; ${bad.length} bypassed a gate: ${bad.slice(0, 12).map((r) => `${r.request_number} (cats ${r.cats}, AI-drafted ${r.ai_drafted}, unscored ${r.unscored}, no policy ${r.no_policy})`).join('; ')}${bad.length > 12 ? ' …' : ''}`)
    expect(bad.length).toBe(0)
  })

  test('TC-DB-016 Committee votes: only committee members, conditions and rationale present', async () => {
    tc({ id: 'TC-DB-016', story: 'US-8.2', type: 'Data', priority: 'P1', steps: ['Join committee_vote to app_user', 'Check blank conditions/rationale', 'Compare decisions with the vote count vs quorum'], expected: 'All voters have role CommitteeMember; no blank conditions/rationale; every decision had >= quorum committee votes' })
    const [s] = await q(db, 'vote scan', `SELECT count(*) AS votes,
      count(*) FILTER (WHERE u.role <> 'CommitteeMember') AS non_member_votes,
      count(*) FILTER (WHERE v.vote = 'ApproveWithConditions' AND coalesce(trim(v.conditions_text),'') = '') AS blank_conditions,
      count(*) FILTER (WHERE v.vote IN ('Reject','Defer') AND coalesce(trim(v.rationale),'') = '') AS blank_rationale
      FROM committee_vote v JOIN app_user u ON u.id = v.committee_member_user_id`)
    const nm = await q(db, 'non-member voters', `SELECT cr.request_number, u.display_name, u.role, v.vote FROM committee_vote v JOIN app_user u ON u.id = v.committee_member_user_id JOIN assessment a ON a.id = v.assessment_id JOIN change_request cr ON cr.id = a.change_request_id WHERE u.role <> 'CommitteeMember'`)
    const [dq] = await q(db, 'decisions vs quorum', `SELECT count(*) AS decisions, count(*) FILTER (WHERE (SELECT count(*) FROM committee_vote v JOIN app_user u ON u.id = v.committee_member_user_id WHERE v.assessment_id = d.assessment_id AND u.role = 'CommitteeMember') < coalesce((SELECT (rule_value->>'quorum')::int FROM workflow_rule WHERE rule_key = 'CommitteeQuorum' AND is_active LIMIT 1), 2)) AS below_quorum FROM committee_decision d`)
    actual(`${s.votes} votes; non-member votes ${s.non_member_votes} (${nm.map((r) => `${r.request_number}: ${r.display_name}/${r.role}=${r.vote}`).join(', ')}); blank conditions ${s.blank_conditions}; blank rationale ${s.blank_rationale}; ${dq.decisions} decisions, ${dq.below_quorum} reached with fewer committee-member votes than quorum`)
    if (n(s.non_member_votes) || n(dq.below_quorum)) defect('DEF-002')
    if (n(s.blank_conditions) || n(s.blank_rationale)) defect('DEF-030')
    expect.soft(n(s.non_member_votes)).toBe(0)
    expect.soft(n(s.blank_conditions)).toBe(0)
    expect.soft(n(s.blank_rationale)).toBe(0)
    expect.soft(n(dq.below_quorum)).toBe(0)
  })

  test('TC-DB-017 Attachments: versions, allowed types, file-extension consistency, extracted text', async () => {
    tc({ id: 'TC-DB-017', story: 'US-1.2 / US-4.1', type: 'Data', priority: 'P2', steps: ['Scan change_request_attachment'], expected: 'Versions > 1 exist where replacements happened; extension matches content type (no .exe stored as PDF); uploaded files have extracted text; superseded chains are consistent' })
    const [s] = await q(db, 'attachment scan', `SELECT count(*) AS files, max(version_number) AS max_version, count(*) FILTER (WHERE superseded_by_attachment_id IS NOT NULL) AS superseded,
      count(*) FILTER (WHERE (content_type = 'application/pdf' AND file_name !~* '\\.pdf$') OR (content_type LIKE '%wordprocessingml%' AND file_name !~* '\\.docx$') OR (content_type LIKE '%spreadsheetml%' AND file_name !~* '\\.xlsx$')) AS ext_mismatch,
      count(*) FILTER (WHERE coalesce(trim(extracted_text),'') = '') AS no_text FROM change_request_attachment`)
    const mism = await q(db, 'extension mismatches', `SELECT file_name, content_type FROM change_request_attachment WHERE (content_type = 'application/pdf' AND file_name !~* '\\.pdf$') OR (content_type LIKE '%wordprocessingml%' AND file_name !~* '\\.docx$') OR (content_type LIKE '%spreadsheetml%' AND file_name !~* '\\.xlsx$')`)
    actual(`${s.files} attachments; max version ${s.max_version}; superseded ${s.superseded}; extension/type mismatches ${s.ext_mismatch} (${mism.map((m) => `${m.file_name} as ${m.content_type}`).join(', ')}); without extracted text ${s.no_text}`)
    test.skip(n(s.files) === 0, 'Not applicable - no attachments stored in this database')
    if (n(s.max_version) <= 1) defect('DEF-008')
    if (n(s.ext_mismatch)) defect('DEF-006')
    expect.soft(n(s.max_version), 'at least one replacement version exists').toBeGreaterThan(1)
    expect.soft(n(s.ext_mismatch), 'stored type matches file extension').toBe(0)
  })

  test('TC-DB-018 Mandatory-content quality of change requests', async () => {
    tc({ id: 'TC-DB-018', story: 'US-1.1', type: 'Data', priority: 'P2', steps: ['Scan change_request text fields and request numbers'], expected: 'No blank title/description; titles within a sane length; request numbers match CR-YYYY-NNNNN and are sequential per year' })
    const [s] = await q(db, 'request quality', `SELECT count(*) AS requests, count(*) FILTER (WHERE trim(title) = '') AS blank_title, count(*) FILTER (WHERE trim(description) = '') AS blank_description, count(*) FILTER (WHERE length(title) > 500) AS overlong_title, count(*) FILTER (WHERE request_number !~ '^CR-\\d{4}-\\d{5}$') AS bad_number, max(length(title)) AS max_title_len FROM change_request`)
    const [g] = await q(db, 'number gaps', `SELECT count(*) AS gaps FROM (SELECT substring(request_number, 9)::int AS nbr, lag(substring(request_number, 9)::int) OVER (PARTITION BY substring(request_number, 4, 4) ORDER BY substring(request_number, 9)::int) AS prev FROM change_request WHERE request_number ~ '^CR-\\d{4}-\\d{5}$') x WHERE prev IS NOT NULL AND nbr <> prev + 1`)
    actual(`${s.requests} requests; blank title ${s.blank_title}, blank description ${s.blank_description}, titles > 500 chars ${s.overlong_title} (max ${s.max_title_len}); malformed numbers ${s.bad_number}; numbering gaps ${g.gaps}`)
    if (n(s.blank_title) || n(s.blank_description) || n(s.overlong_title)) defect('DEF-009')
    expect(n(s.bad_number)).toBe(0)
    expect.soft(n(s.blank_title) + n(s.blank_description)).toBe(0)
    expect.soft(n(s.overlong_title)).toBe(0)
    expect.soft(n(g.gaps), 'gaps may indicate failed/rolled-back submissions').toBe(0)
  })

  test('TC-DB-019 Policy reliance: one decision per (assessment, category, passage)', async () => {
    tc({ id: 'TC-DB-019', story: 'US-3.2', type: 'Data', priority: 'P2', steps: ['Inspect the unique key on assessment_policy_reliance'], expected: 'Unique key includes risk_category_id so the same passage can be relied upon for several categories' })
    defect('DEF-011')
    const idx = await q(db, 'reliance unique key', `SELECT pg_get_constraintdef(oid) AS def FROM pg_constraint WHERE conrelid = 'assessment_policy_reliance'::regclass AND contype = 'u'`)
    actual(`unique constraint(s): ${idx.map((i) => i.def).join('; ')}`)
    expect(idx.some((i) => /risk_category_id/.test(i.def))).toBe(true)
  })
})

test.describe('Audit trail completeness', () => {
  test('TC-DB-020 Every human action in the audit trail names a user; every override/edit has a reason', async () => {
    tc({ id: 'TC-DB-020', story: 'US-9.1 / US-6.1', type: 'Data', priority: 'P1', steps: ['Scan audit_event by actor_label and action'], expected: "actor_label 'human' rows always have actor_user_id; 'system/AI' rows never do; Overridden/Edited/Corrected/ConfigChanged rows always carry a reason; no timestamps in the future" })
    const [s] = await q(db, 'audit scan', `SELECT count(*) AS events,
      count(*) FILTER (WHERE actor_label = 'human' AND actor_user_id IS NULL) AS human_no_user,
      count(*) FILTER (WHERE actor_label NOT IN ('human','system/AI')) AS bad_label,
      count(*) FILTER (WHERE action ~* '(overrid|edit|correct|configchang|removed|added)' AND coalesce(trim(reason),'') = '') AS change_no_reason,
      count(*) FILTER (WHERE created_at > now() + interval '5 minutes') AS future,
      count(*) FILTER (WHERE change_request_id IS NULL AND assessment_id IS NULL AND entity_type NOT IN ('ScoringConfig','WorkflowRule')) AS unanchored
      FROM audit_event`)
    const noReason = await q(db, 'changes without reason', `SELECT entity_type, action, count(*) AS n FROM audit_event WHERE action ~* '(overrid|edit|correct|configchang|removed|added)' AND coalesce(trim(reason),'') = '' GROUP BY 1, 2 ORDER BY 3 DESC`)
    actual(`${s.events} events; human without user ${s.human_no_user}; unknown actor label ${s.bad_label}; change events without reason ${s.change_no_reason} (${noReason.map((r) => `${r.entity_type}.${r.action}=${r.n}`).join(', ')}); future timestamps ${s.future}; not linked to a request/assessment ${s.unanchored}`)
    expect(n(s.human_no_user)).toBe(0)
    expect(n(s.bad_label)).toBe(0)
    expect(n(s.future)).toBe(0)
    expect.soft(n(s.change_no_reason)).toBe(0)
    expect.soft(n(s.unanchored)).toBe(0)
  })

  test('TC-DB-021 Every domain record has a matching audit event', async () => {
    tc({ id: 'TC-DB-021', story: 'US-9.1', type: 'Data', priority: 'P1', steps: ['For requests, attachments, category mappings, narratives, scores, votes and decisions check an audit_event references them'], expected: 'No domain record without an audit event (nothing reached the database outside the audited functions); seed-time config rows are excluded' })
    const rows = await q(db, 'audit coverage', `SELECT 'change_request' AS entity, count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM audit_event e WHERE e.change_request_id = x.id AND e.entity_type = 'ChangeRequest')) AS missing, count(*) AS total FROM change_request x
      UNION ALL SELECT 'attachment', count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM audit_event e WHERE e.entity_id = x.id)), count(*) FROM change_request_attachment x
      UNION ALL SELECT 'category_mapping', count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM audit_event e WHERE e.assessment_id = x.assessment_id AND e.entity_type = 'CategoryMapping')), count(*) FROM assessment_category_mapping x
      UNION ALL SELECT 'narrative', count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM audit_event e WHERE e.entity_id = x.id)), count(*) FROM assessment_narrative_section x
      UNION ALL SELECT 'risk_score', count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM audit_event e WHERE e.entity_id = x.id)), count(*) FROM assessment_risk_score x
      UNION ALL SELECT 'committee_vote', count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM audit_event e WHERE e.entity_id = x.id)), count(*) FROM committee_vote x
      UNION ALL SELECT 'committee_decision', count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM audit_event e WHERE e.entity_id = x.id OR (e.assessment_id = x.assessment_id AND e.entity_type = 'CommitteeDecision'))), count(*) FROM committee_decision x
      UNION ALL SELECT 'scoring_config (post-seed)', count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM audit_event e WHERE e.entity_id = x.id)), count(*) FROM scoring_config x WHERE x.created_at > (SELECT min(created_at) + interval '10 minutes' FROM app_user)
      UNION ALL SELECT 'workflow_rule (post-seed)', count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM audit_event e WHERE e.entity_id = x.id)), count(*) FROM workflow_rule x WHERE x.created_at > (SELECT min(created_at) + interval '10 minutes' FROM app_user)`)
    actual(rows.map((r) => `${r.entity}: ${r.missing}/${r.total} unaudited`).join('; '))
    for (const r of rows) expect.soft(n(r.missing), r.entity).toBe(0)
  })

  test('TC-DB-022 Overwritten votes left an audit trail of the previous value', async () => {
    tc({ id: 'TC-DB-022', story: 'US-8.2 / US-9.2', type: 'Data', priority: 'P2', steps: ['Find votes with more than one CommitteeVote audit event', 'Compare the audited values with the stored vote'], expected: 'No vote has been silently replaced - every vote row matches its only audit event' })
    defect('DEF-003')
    const rows = await q(db, 'revotes', `SELECT cr.request_number, u.display_name, v.vote AS stored_vote, count(e.id) AS audit_events, string_agg(coalesce(e.after_value->>'vote', '?'), ' -> ' ORDER BY e.created_at) AS history
      FROM committee_vote v JOIN app_user u ON u.id = v.committee_member_user_id JOIN assessment a ON a.id = v.assessment_id JOIN change_request cr ON cr.id = a.change_request_id
      LEFT JOIN audit_event e ON e.entity_id = v.id AND e.entity_type = 'CommitteeVote' GROUP BY cr.request_number, u.display_name, v.vote HAVING count(e.id) > 1`)
    actual(rows.length ? `${rows.length} vote rows were overwritten: ${rows.slice(0, 10).map((r) => `${r.request_number} ${r.display_name}: ${r.history} (stored ${r.stored_vote})`).join('; ')}` : 'no overwritten votes')
    expect(rows.length).toBe(0)
  })
})

test.describe('Cross-system consistency & data hygiene', () => {
  test('TC-DB-030 External snapshots reference real mock-system records', async () => {
    tc({ id: 'TC-DB-030', story: 'Data ingestion', type: 'Data', priority: 'P2', steps: ['Join change_request_external_snapshot to mock_systems tables'], expected: 'Every snapshot id resolves to an existing mock customer/product/vendor and carries its risk context' })
    const [s] = await q(db, 'snapshot resolution', `SELECT count(*) AS snapshots,
      count(*) FILTER (WHERE mock_customer_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM mock_systems.crm_customer c WHERE c.id = x.mock_customer_id)) AS dangling_customer,
      count(*) FILTER (WHERE mock_product_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM mock_systems.core_banking_product p WHERE p.id = x.mock_product_id)) AS dangling_product,
      count(*) FILTER (WHERE mock_vendor_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM mock_systems.vendor_registry v WHERE v.id = x.mock_vendor_id)) AS dangling_vendor,
      count(*) FILTER (WHERE (mock_customer_id IS NOT NULL AND customer_risk_context IS NULL) OR (mock_product_id IS NOT NULL AND product_risk_context IS NULL) OR (mock_vendor_id IS NOT NULL AND vendor_risk_context IS NULL)) AS missing_context
      FROM change_request_external_snapshot x`)
    actual(`${s.snapshots} snapshots; dangling customer ${s.dangling_customer}, product ${s.dangling_product}, vendor ${s.dangling_vendor}; missing risk context ${s.missing_context}`)
    expect(n(s.dangling_customer) + n(s.dangling_product) + n(s.dangling_vendor)).toBe(0)
    expect.soft(n(s.missing_context)).toBe(0)
  })

  test('TC-DB-031 Committee decisions are fed back to the linked mock-system record', async () => {
    tc({ id: 'TC-DB-031', story: 'Data ingestion feedback loop', type: 'Data', priority: 'P2', steps: ['For decided requests with a linked mock entity, check the entity\'s written-back risk fields'], expected: 'Each decided product has go_live_flag/risk_rating set, each vendor updated_risk_rating, each customer risk_flag' })
    const rows = await q(db, 'feedback loop', `SELECT cr.request_number, d.resolution,
      CASE WHEN x.mock_product_id IS NOT NULL THEN (SELECT (p.go_live_flag IS NOT NULL AND p.risk_rating IS NOT NULL) FROM mock_systems.core_banking_product p WHERE p.id = x.mock_product_id)
           WHEN x.mock_vendor_id IS NOT NULL THEN (SELECT v.updated_risk_rating IS NOT NULL FROM mock_systems.vendor_registry v WHERE v.id = x.mock_vendor_id)
           WHEN x.mock_customer_id IS NOT NULL THEN (SELECT c.risk_flag IS NOT NULL FROM mock_systems.crm_customer c WHERE c.id = x.mock_customer_id) END AS written_back
      FROM committee_decision d JOIN assessment a ON a.id = d.assessment_id JOIN change_request cr ON cr.id = a.change_request_id JOIN change_request_external_snapshot x ON x.change_request_id = cr.id
      WHERE coalesce(x.mock_product_id, x.mock_vendor_id, x.mock_customer_id) IS NOT NULL`)
    const missing = rows.filter((r) => r.written_back !== true)
    actual(`${rows.length} decided requests linked to a mock entity; not written back: ${missing.length} ${missing.map((r) => r.request_number).join(', ')}`)
    expect(missing.length).toBe(0)
  })

  test('TC-DB-032 Only synthetic data - no real-looking PII in free text', async () => {
    tc({ id: 'TC-DB-032', story: 'Hackathon constraint: synthetic data only', type: 'Data', priority: 'P1', steps: ['Regex-scan change requests, extracted fields, narratives, votes and mock customers for SSN, card-number, IBAN and non-example e-mail patterns'], expected: 'No matches' })
    const rows = await q(db, 'pii scan', `WITH t AS (
        SELECT 'change_request' AS src, request_number AS ref, title || ' ' || description || ' ' || type_specific_fields::text AS txt FROM change_request
        UNION ALL SELECT 'extracted_field', field_key, coalesce(field_value,'') || ' ' || coalesce(source_excerpt,'') FROM extracted_field
        UNION ALL SELECT 'narrative', id::text, narrative_text FROM assessment_narrative_section
        UNION ALL SELECT 'committee_vote', id::text, coalesce(conditions_text,'') || ' ' || coalesce(rationale,'') FROM committee_vote
        UNION ALL SELECT 'crm_customer', id::text, customer_name FROM mock_systems.crm_customer)
      SELECT src, ref, CASE WHEN txt ~ '\\m\\d{3}-\\d{2}-\\d{4}\\M' THEN 'SSN' WHEN txt ~ '\\m(?:\\d[ -]?){15,16}\\M' THEN 'card-number' WHEN txt ~ '\\m[A-Z]{2}\\d{2}[A-Z0-9]{11,30}\\M' THEN 'IBAN' ELSE 'e-mail' END AS kind
      FROM t WHERE txt ~ '\\m\\d{3}-\\d{2}-\\d{4}\\M' OR txt ~ '\\m(?:\\d[ -]?){15,16}\\M' OR txt ~ '\\m[A-Z]{2}\\d{2}[A-Z0-9]{11,30}\\M' OR txt ~* '[a-z0-9._%+-]+@(?!example\\.)[a-z0-9.-]+\\.[a-z]{2,}'`)
    actual(rows.length ? `${rows.length} suspicious values: ${rows.slice(0, 10).map((r) => `${r.src}/${r.ref}: ${r.kind}`).join(', ')}` : 'no PII-like patterns found')
    expect(rows).toEqual([])
  })

  test('TC-DB-033 Reference-data coverage: controls library and policy corpus per category', async () => {
    tc({ id: 'TC-DB-033', story: 'US-7.1 / US-3.1', type: 'Data', priority: 'P2', steps: ['Count control and policy_chunk rows per category', 'Check policy_document source URL / version label'], expected: 'Each category has >= 1 control and >= 3 policy passages; every policy document has a source URL and version' })
    const rows = await q(db, 'coverage', `SELECT c.code, (SELECT count(*) FROM control k WHERE k.risk_category_id = c.id) AS controls, (SELECT count(*) FROM policy_chunk p WHERE p.risk_category_id = c.id) AS passages FROM risk_category c ORDER BY 1`)
    const [docs] = await q(db, 'policy documents', `SELECT count(*) AS docs, count(*) FILTER (WHERE source_url !~ '^https?://' OR coalesce(trim(version_label),'') = '') AS incomplete, (SELECT count(*) FROM policy_chunk) AS chunks FROM policy_document`)
    actual(`${rows.map((r) => `${r.code}: ${r.controls} controls, ${r.passages} passages`).join('; ')}; ${docs.docs} policy documents (${docs.incomplete} missing URL/version), ${docs.chunks} passages total`)
    if (rows.some((r) => n(r.controls) === 0)) defect('DEF-013')
    if (rows.some((r) => n(r.passages) < 3)) defect('DEF-032')
    for (const r of rows) {
      expect.soft(n(r.controls), `${r.code} controls`).toBeGreaterThan(0)
      expect.soft(n(r.passages), `${r.code} passages`).toBeGreaterThanOrEqual(3)
    }
    expect(n(docs.incomplete)).toBe(0)
  })

  test('TC-DB-034 Workflow rules: one active version per key, well-formed values', async () => {
    tc({ id: 'TC-DB-034', story: 'US-10.2', type: 'Data', priority: 'P2', steps: ['Group workflow_rule by key/is_active', 'Validate CommitteeQuorum JSON'], expected: 'Exactly one active row per rule key; CommitteeQuorum.quorum is a positive integer; every version has a reason' })
    const rows = await q(db, 'workflow rules', `SELECT rule_key, count(*) FILTER (WHERE is_active) AS active, count(*) AS versions, max(rule_value::text) FILTER (WHERE is_active) AS value, count(*) FILTER (WHERE coalesce(trim(reason),'') = '') AS no_reason FROM workflow_rule GROUP BY 1`)
    const q2 = rows.find((r) => r.rule_key === 'CommitteeQuorum')
    actual(rows.map((r) => `${r.rule_key}: active=${r.active}, versions=${r.versions}, value=${r.value}, blankReason=${r.no_reason}`).join('; '))
    for (const r of rows) expect(n(r.active), r.rule_key).toBe(1)
    expect(Number(JSON.parse(q2.value).quorum)).toBeGreaterThan(0)
  })

  test('TC-DB-035 QA test-data footprint (informational)', async () => {
    tc({ id: 'TC-DB-035', story: 'Test data management', type: 'Data', priority: 'P3', steps: ['Count rows created by the QA suites ([QA-E2E prefix)'], expected: 'Informational - lets the team purge QA data before the demo' })
    const [s] = await q(db, 'qa footprint', `SELECT count(*) AS requests, count(*) FILTER (WHERE status = 'PendingCommittee') AS still_in_queue, (SELECT count(*) FROM change_request) AS all_requests FROM change_request WHERE title LIKE '[QA-E2E%'`)
    actual(`${s.requests} of ${s.all_requests} change requests are QA-generated; ${s.still_in_queue} still in the committee queue. Because the audit trail is append-only, removing them needs an agreed purge approach (e.g. a demo-reset script run by the DB owner).`)
    expect(n(s.requests)).toBeGreaterThanOrEqual(0)
  })
})
