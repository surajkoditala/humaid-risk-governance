import fs from 'node:fs'
import path from 'node:path'
import { expect, test } from '@playwright/test'
import { actual, call, defect, FIXTURES, qaTitle, tc } from '../../lib/harness'
import { userId, USERS } from '../../lib/app'
import { state } from '../../lib/state'

// One synthetic Vendor-onboarding request walked all the way from intake to a committee decision
// through the API, with every governance gate probed on the way. Ids are persisted via lib/state
// so a failed probe doesn't strand the rest of the lifecycle.
const K = (k: string) => `api.${k}`
const CAT = {
  products: '22222222-2222-2222-2222-222222222221',
  customers: '22222222-2222-2222-2222-222222222222',
  geo: '22222222-2222-2222-2222-222222222223',
  channels: '22222222-2222-2222-2222-222222222224',
}
const DOC_TEXT = fs.readFileSync(path.join(FIXTURES, 'vendor-due-diligence.pdf'), 'latin1').match(/\((.*?)\) Tj/g)!.map((s) => s.slice(1, -4)).join(' ')

test.describe('Assessment lifecycle (API)', () => {
  test.describe.configure({ timeout: 240_000 })

  test('TC-API-030 Open assessment workspace is idempotent', async ({ request }) => {
    tc({ id: 'TC-API-030', story: 'US-6.3', type: 'API', priority: 'P1', steps: ['Submit a Vendor request (PO) linked to a mock vendor', 'POST /api/Assessment/OpenWorkspace/{crId} twice', 'GET /api/Assessment/ByChangeRequest/{crId}'], expected: 'Both calls return the same assessment id; the request moves to InAssessment' })
    const po = await userId(request, USERS.po)
    const vendors = await call(request, 'GET', '/api/DataIngestion/MockVendors', { label: 'vendors' })
    const cr = await call(request, 'POST', '/api/ChangeRequest/Submit', {
      data: { changeType: 'Vendor', title: qaTitle('API lifecycle - onboard settlement vendor'), description: 'Onboard a Malta-based card settlement processor with access to cardholder PII.', typeSpecificFieldsJson: JSON.stringify({ details: 'Vendor: QuickPay; jurisdiction: Malta; data access: cardholder PII' }), submittedByUserId: po, mockVendorId: vendors.body.data[0].id },
      label: 'submit',
    })
    expect(cr.status).toBe(200)
    state.set(K('crId'), cr.body.data.id)
    state.set(K('crNumber'), cr.body.data.requestNumber)
    const up = await call(request, 'POST', '/api/ChangeRequest/AttachDocumentFile', {
      multipart: { changeRequestId: cr.body.data.id, uploadedByUserId: po, file: { name: 'vendor-due-diligence.pdf', mimeType: 'application/pdf', buffer: fs.readFileSync(path.join(FIXTURES, 'vendor-due-diligence.pdf')) } },
      label: 'attach pdf',
    })
    state.set(K('attachmentId'), up.body?.data?.id)
    const a = await call(request, 'POST', `/api/Assessment/OpenWorkspace/${cr.body.data.id}`, { label: 'open #1' })
    const b = await call(request, 'POST', `/api/Assessment/OpenWorkspace/${cr.body.data.id}`, { label: 'open #2' })
    expect(a.status).toBe(200)
    expect(b.body.data).toBe(a.body.data)
    state.set(K('assessmentId'), a.body.data)
    const after = await call(request, 'GET', `/api/ChangeRequest/${cr.body.data.id}`, { label: 'cr after open' })
    actual(`${cr.body.data.requestNumber}: assessment ${a.body.data} (same on 2nd open: ${b.body.data === a.body.data}); status ${after.body.data.status}`)
    expect(after.body.data.status).toBe('InAssessment')
  })

  test('TC-API-031 Finalize and route are blocked while nothing has been reviewed', async ({ request }) => {
    tc({ id: 'TC-API-031', story: 'US-6.3 / US-8.1', type: 'Negative', priority: 'P1', steps: ['Submit a separate "probe" request and open its workspace (no categories, no narrative, no policy)', 'GET Readiness', 'POST Finalize', 'POST Committee/Route'], expected: 'Readiness is false; Finalize and Route rejected (400) with the outstanding items listed' })
    // Run on a throwaway request so that, if the gate is broken, the main lifecycle isn't derailed.
    const po = await userId(request, USERS.po)
    const an = await userId(request, USERS.analyst)
    const cr = await call(request, 'POST', '/api/ChangeRequest/Submit', { data: { changeType: 'Feature', title: qaTitle('API probe - empty assessment'), description: 'Nothing will be reviewed on this one', submittedByUserId: po }, label: 'submit probe' })
    const id = (await call(request, 'POST', `/api/Assessment/OpenWorkspace/${cr.body.data.id}`, { label: 'open probe' })).body.data
    const ready = await call(request, 'GET', `/api/Assessment/${id}/Readiness`, { label: 'readiness' })
    const fin = await call(request, 'POST', `/api/Assessment/${id}/Finalize`, { data: { actorUserId: an }, label: 'finalize' })
    const route = await call(request, 'POST', '/api/Committee/Route', { data: { assessmentId: id, actorUserId: an }, label: 'route' })
    const q = await call(request, 'GET', '/api/Committee/Queue', { label: 'queue' })
    actual(`${cr.body.data.requestNumber}: readiness.isReady=${ready.body.data.isReady} with 0 categories; finalize -> ${fin.status} "${fin.body.message ?? fin.body.data}"; route -> ${route.status} "${route.body.message ?? route.body.data}"; in committee queue: ${q.body.data.some((x: any) => x.assessmentId === id)}`)
    if (route.status === 200) state.set(K('probeAssessmentId'), id)
    defect('DEF-001')
    expect.soft(ready.body.data.isReady, 'an assessment with no mapped categories is not "ready"').toBe(false)
    expect.soft(fin.status, 'finalize with zero categories mapped must be blocked').toBe(400)
    expect.soft(route.status).toBe(400)
  })

  test('TC-API-032 AI proposes FFIEC categories with citations for a Vendor request', async ({ request }) => {
    tc({ id: 'TC-API-032', story: 'US-2.1', type: 'API', priority: 'P1', steps: ['POST /api/CategoryMapping/Propose?assessmentId&changeRequestId (Azure AI Foundry)'], expected: 'Only FFIEC categories; Vendor maps to Customers & Entities + Delivery Channels; each row has a citation; source AiProposed' })
    const id = state.need(K('assessmentId'))
    const crId = state.need(K('crId'))
    // If TC-API-031 wrongly finalized the assessment, a new request is needed to keep going.
    const r = await call(request, 'POST', `/api/CategoryMapping/Propose?assessmentId=${id}&changeRequestId=${crId}`, { label: 'propose (AI)' })
    expect(r.status).toBe(200)
    actual(`AI proposed in ${r.ms} ms: ${r.body.data.map((m: any) => `${m.categoryName} [${m.source}] "${(m.aiCitation || '').slice(0, 80)}"`).join(' ; ')}`)
    const names = r.body.data.filter((m: any) => m.isActive).map((m: any) => m.categoryName)
    for (const m of r.body.data) {
      expect(Object.values(CAT)).toContain(m.riskCategoryId)
      expect(m.aiCitation || m.citationSection).toBeTruthy()
    }
    defect('DEF-012')
    expect(names, 'CLAUDE.md mapping: Vendor onboarding -> Customers/Entities + Delivery Channels').toEqual(expect.arrayContaining(['Customers & Entities', 'Delivery Channels']))
  })

  test('TC-API-033 Category override requires a reason; AI original retained', async ({ request }) => {
    tc({ id: 'TC-API-033', story: 'US-2.2 / US-6.1', type: 'Negative', priority: 'P1', steps: ['POST CategoryMapping/Override (add Geographic Locations) with empty reason', 'Repeat with a reason', 'Remove Delivery Channels with a reason, then re-add it', 'GET mapping and audit trail'], expected: 'Blank reason -> 400; with reason -> saved; audit shows the AI proposal and each override with its reason' })
    const id = state.need(K('assessmentId'))
    const crId = state.need(K('crId'))
    const an = await userId(request, USERS.analyst)
    const noReason = await call(request, 'POST', '/api/CategoryMapping/Override', { data: { assessmentId: id, riskCategoryId: CAT.geo, isActive: true, reason: '  ', actorUserId: an }, label: 'override blank reason' })
    const add = await call(request, 'POST', '/api/CategoryMapping/Override', { data: { assessmentId: id, riskCategoryId: CAT.geo, isActive: true, reason: 'Vendor is domiciled in Malta - geographic exposure', actorUserId: an }, label: 'add geo' })
    const rm = await call(request, 'POST', '/api/CategoryMapping/Override', { data: { assessmentId: id, riskCategoryId: CAT.channels, isActive: false, reason: 'QA: removal test', actorUserId: an }, label: 'remove channels' })
    const readd = await call(request, 'POST', '/api/CategoryMapping/Override', { data: { assessmentId: id, riskCategoryId: CAT.channels, isActive: true, reason: 'QA: restore - API channel is non-face-to-face', actorUserId: an }, label: 're-add channels' })
    const map = await call(request, 'GET', `/api/CategoryMapping/${id}`, { label: 'mapping' })
    const trail = await call(request, 'GET', `/api/Audit/${crId}`, { label: 'audit' })
    const mappingEvents = trail.body.data.filter((e: any) => /Category/i.test(e.entityType))
    actual(`blank reason -> ${noReason.status} "${noReason.body.message}"; add -> ${add.status}; remove -> ${rm.status}; re-add -> ${readd.status}; active now: ${map.body.data.filter((m: any) => m.isActive).map((m: any) => m.categoryName).join(', ')}; ${mappingEvents.length} category audit events`)
    expect(noReason.status).toBe(400)
    expect(add.status).toBe(200)
    expect(map.body.data.filter((m: any) => m.isActive).map((m: any) => m.riskCategoryId)).toContain(CAT.geo)
    expect(mappingEvents.some((e: any) => e.reason?.includes('Malta'))).toBeTruthy()
    state.set(K('activeCats'), map.body.data.filter((m: any) => m.isActive).map((m: any) => m.riskCategoryId))
  })

  test('TC-API-040 Policy search returns ranked, citable FFIEC/FATF passages', async ({ request }) => {
    tc({ id: 'TC-API-040', story: 'US-3.1', type: 'API', priority: 'P1', steps: ['GET PolicyResearch/Search?queryText=beneficial ownership', 'GET with riskCategoryId filter', 'GET with nonsense text'], expected: 'Ranked results (rank desc) each with document title, source URL, section ref and effective date; nonsense -> empty list' })
    const r = await call(request, 'GET', `/api/PolicyResearch/Search?queryText=${encodeURIComponent('beneficial ownership')}&topK=5`, { label: 'search' })
    const f = await call(request, 'GET', `/api/PolicyResearch/Search?queryText=${encodeURIComponent('customer due diligence')}&riskCategoryId=${CAT.customers}&topK=5`, { label: 'search filtered' })
    const none = await call(request, 'GET', `/api/PolicyResearch/Search?queryText=zzqxv%20plorbnak&topK=5`, { label: 'search nonsense' })
    expect(r.status).toBe(200)
    expect(r.body.data.length).toBeGreaterThan(0)
    const ranks = r.body.data.map((x: any) => x.rank)
    expect([...ranks].sort((a, b) => b - a)).toEqual(ranks)
    for (const x of r.body.data) {
      expect(x.sectionRef).toBeTruthy()
      expect(x.sourceUrl).toMatch(/^https?:\/\//)
    }
    expect(none.body.data).toEqual([])
    // The seeded corpus is small; take distinct passages from a broad query so each mapped
    // category can get its own reliance decision.
    const broad = await call(request, 'GET', `/api/PolicyResearch/Search?queryText=bank&topK=10`, { label: 'search broad' })
    state.set(K('chunkIds'), broad.body.data.map((x: any) => x.id))
    actual(`"beneficial ownership": ${r.body.data.length} hits in ${r.ms} ms, top = ${r.body.data[0].documentTitle} ${r.body.data[0].sectionRef} (${r.body.data[0].sourceUrl}), effectiveDate=${r.body.data[0].effectiveDate}; filtered: ${f.body.data.length}; nonsense: ${none.body.data.length}`)
  })

  test('TC-API-041 Policy search input validation / injection safety', async ({ request }) => {
    tc({ id: 'TC-API-041', story: 'US-3.1 / NFR-SEC', type: 'Security', priority: 'P2', steps: ["Search queryText=' OR 1=1; DROP TABLE policy_chunk;--", 'Search queryText=<script>alert(1)</script>', 'Search with empty queryText', 'Search topK=100000'], expected: 'No 500s; injection payloads treated as literal text; empty query rejected (400) or returns []; topK capped' })
    const inj = await call(request, 'GET', `/api/PolicyResearch/Search?queryText=${encodeURIComponent("' OR 1=1; DROP TABLE policy_chunk;--")}`, { label: 'sqli' })
    const xss = await call(request, 'GET', `/api/PolicyResearch/Search?queryText=${encodeURIComponent('<script>alert(1)</script>')}`, { label: 'xss' })
    const empty = await call(request, 'GET', `/api/PolicyResearch/Search?queryText=`, { label: 'empty' })
    const big = await call(request, 'GET', `/api/PolicyResearch/Search?queryText=bank&topK=100000`, { label: 'topK huge' })
    const still = await call(request, 'GET', `/api/PolicyResearch/Search?queryText=beneficial%20ownership`, { label: 'corpus still intact' })
    actual(`sqli -> ${inj.status} (${inj.body?.data?.length ?? '-'} rows); xss -> ${xss.status}; empty -> ${empty.status}; topK=100000 -> ${big.status} (${big.body?.data?.length ?? '-'} rows); corpus intact -> ${still.body?.data?.length} rows`)
    expect(inj.status).toBeLessThan(500)
    expect(xss.status).toBeLessThan(500)
    expect(empty.status).toBeLessThan(500)
    expect(still.body.data.length).toBeGreaterThan(0)
    expect.soft(big.body?.data?.length ?? 0, 'topK should be capped server-side').toBeLessThanOrEqual(50)
  })

  test('TC-API-044 Policy corpus covers the core FFIEC risk topics', async ({ request }) => {
    const topics = ['wire transfer', 'correspondent banking', 'politically exposed', 'sanctions', 'money services business', 'prepaid', 'cash-intensive', 'high-risk jurisdiction']
    tc({ id: 'TC-API-044', story: 'US-3.1 / RAG', type: 'API', priority: 'P2', steps: topics.map((t) => `Search "${t}"`), expected: 'At least one relevant passage for each core FFIEC / FATF topic the categories rely on' })
    const hits: string[] = []
    let missing = 0
    for (const t of topics) {
      const r = await call(request, 'GET', `/api/PolicyResearch/Search?queryText=${encodeURIComponent(t)}&topK=5`, { label: t })
      hits.push(`${t}=${r.body.data.length}`)
      if (r.body.data.length === 0) missing++
      expect.soft(r.body.data.length, t).toBeGreaterThan(0)
    }
    const broad = await call(request, 'GET', `/api/PolicyResearch/Search?queryText=bank&topK=50`, { label: 'corpus size probe' })
    actual(`${hits.join(', ')}; ${missing}/${topics.length} topics have no passage; broad query returns ${broad.body.data.length} passages in total`)
    defect('DEF-032')
  })

  test('TC-API-042 Record policy reliance decisions', async ({ request }) => {
    tc({ id: 'TC-API-042', story: 'US-3.2', type: 'API', priority: 'P1', steps: ['RecordReliance ReliedUpon for each active category', 'RecordReliance NotRelevant for another chunk', 'RecordReliance with decision "Maybe"', 'GET reliance'], expected: 'Valid decisions recorded; invalid decision rejected with 400' })
    const id = state.need(K('assessmentId'))
    const cats: string[] = state.need(K('activeCats'))
    const an = await userId(request, USERS.analyst)
    const chunks: string[] = state.need(K('chunkIds'))
    cats.forEach((_, i) => expect(chunks[i], 'enough distinct passages for each category').toBeTruthy())
    for (const [i, c] of cats.entries()) {
      const r = await call(request, 'POST', '/api/PolicyResearch/RecordReliance', { data: { assessmentId: id, riskCategoryId: c, policyChunkId: chunks[i], decision: 'ReliedUpon', decidedByUserId: an }, label: `relied ${c.slice(-1)}` })
      expect(r.status).toBe(200)
    }
    const spare = chunks[cats.length] ?? chunks[chunks.length - 1]
    const nr = await call(request, 'POST', '/api/PolicyResearch/RecordReliance', { data: { assessmentId: id, riskCategoryId: cats[0], policyChunkId: spare, decision: 'NotRelevant', decidedByUserId: an }, label: 'not relevant' })
    const bad = await call(request, 'POST', '/api/PolicyResearch/RecordReliance', { data: { assessmentId: id, riskCategoryId: cats[0], policyChunkId: spare, decision: 'Maybe', decidedByUserId: an }, label: 'invalid decision' })
    const list = await call(request, 'GET', `/api/PolicyResearch/${id}/Reliance`, { label: 'reliance' })
    actual(`${cats.length} ReliedUpon + NotRelevant(${nr.status}) recorded; list has ${list.body.data.length}; invalid "Maybe" -> ${bad.status} "${bad.body.message}"`)
    expect(nr.status).toBe(200)
    expect(list.body.data.length).toBeGreaterThanOrEqual(cats.length + 1)
    expect.soft(bad.status, 'invalid enum should be a 400, not a 500').toBe(400)
    if (bad.status !== 400) defect('DEF-005')
  })

  test('TC-API-043 One passage relied upon for two categories keeps both decisions', async ({ request }) => {
    tc({ id: 'TC-API-043', story: 'US-3.2 / US-9.1', type: 'Negative', priority: 'P2', steps: ['On the probe assessment: RecordReliance chunk X for Customers & Entities', 'RecordReliance the same chunk X for Delivery Channels', 'GET reliance'], expected: 'Two reliance rows (one per category) - the second decision does not overwrite the first' })
    const id = state.need(K('probeAssessmentId'))
    const chunks: string[] = state.need(K('chunkIds'))
    const an = await userId(request, USERS.analyst)
    const a = await call(request, 'POST', '/api/PolicyResearch/RecordReliance', { data: { assessmentId: id, riskCategoryId: CAT.customers, policyChunkId: chunks[0], decision: 'ReliedUpon', decidedByUserId: an }, label: 'chunk X for customers' })
    const b = await call(request, 'POST', '/api/PolicyResearch/RecordReliance', { data: { assessmentId: id, riskCategoryId: CAT.channels, policyChunkId: chunks[0], decision: 'ReliedUpon', decidedByUserId: an }, label: 'chunk X for channels' })
    const list = await call(request, 'GET', `/api/PolicyResearch/${id}/Reliance`, { label: 'reliance' })
    const rows = list.body.data.filter((r: any) => r.policyChunkId === chunks[0])
    actual(`ids returned: ${a.body.data} / ${b.body.data} (${a.body.data === b.body.data ? 'SAME row' : 'distinct'}); rows for chunk X: ${rows.map((r: any) => r.riskCategoryId?.slice(-1)).join(',')}`)
    defect('DEF-011')
    expect(rows.length).toBe(2)
  })

  test('TC-API-050 AI extracts structured fields from the document with confidence and source excerpts', async ({ request }) => {
    tc({ id: 'TC-API-050', story: 'US-4.1', type: 'API', priority: 'P1', steps: ['POST DocumentExtraction/Extract with the due-diligence document text', 'GET extracted fields'], expected: 'Key/value fields (e.g. jurisdiction = Malta) each with confidence, needsReview flag and source excerpt; source AiExtracted' })
    const crId = state.need(K('crId'))
    const r = await call(request, 'POST', '/api/DocumentExtraction/Extract', { data: { changeRequestId: crId, attachmentId: state.get(K('attachmentId')), changeType: 'Vendor', documentText: DOC_TEXT }, label: 'extract (AI)' })
    expect(r.status).toBe(200)
    expect(r.body.data.length).toBeGreaterThan(0)
    const flat = JSON.stringify(r.body.data)
    expect(flat).toMatch(/Malta/)
    for (const f of r.body.data) expect(f).toHaveProperty('needsReview')
    state.set(K('fieldKey'), r.body.data[0].fieldKey)
    actual(`${r.ms} ms: ${r.body.data.map((f: any) => `${f.fieldKey}=${f.fieldValue} (conf ${f.confidence}, review=${f.needsReview})`).join('; ')}`)
  })

  test('TC-API-051 Extracted-field correction: material change needs a reason; original retained', async ({ request }) => {
    tc({ id: 'TC-API-051', story: 'US-4.2', type: 'Negative', priority: 'P1', steps: ['Correct field with isMaterialChange=true and no reason', 'Correct with isMaterialChange=false and no reason (formatting)', 'Correct with material change and a reason', 'GET fields + audit'], expected: 'Material/no-reason -> 400; trivial/no-reason -> 200; material with reason -> 200; audit keeps AI original and corrected value' })
    const crId = state.need(K('crId'))
    const key = state.need(K('fieldKey'))
    const an = await userId(request, USERS.analyst)
    const a = await call(request, 'POST', '/api/DocumentExtraction/Correct', { data: { input: { changeRequestId: crId, fieldKey: key, newValue: 'QA value', reason: '', actorUserId: an }, isMaterialChange: true }, label: 'material no reason' })
    const b = await call(request, 'POST', '/api/DocumentExtraction/Correct', { data: { input: { changeRequestId: crId, fieldKey: key, newValue: 'QA value ', actorUserId: an }, isMaterialChange: false }, label: 'trivial no reason' })
    const c = await call(request, 'POST', '/api/DocumentExtraction/Correct', { data: { input: { changeRequestId: crId, fieldKey: key, newValue: 'QA corrected value', reason: 'Contract section 4 states otherwise', actorUserId: an }, isMaterialChange: true }, label: 'material with reason' })
    const fields = await call(request, 'GET', `/api/DocumentExtraction/${crId}`, { label: 'fields' })
    const trail = await call(request, 'GET', `/api/Audit/${crId}`, { label: 'audit' })
    const ev = trail.body.data.filter((e: any) => /Extract/i.test(e.entityType))
    actual(`material/no reason -> ${a.status} "${a.body.message}"; trivial -> ${b.status}; material+reason -> ${c.status}; ${ev.length} extraction audit events; field ${key} now "${fields.body.data.find((f: any) => f.fieldKey === key)?.fieldValue}"`)
    expect(a.status).toBe(400)
    expect(b.status).toBe(200)
    expect(c.status).toBe(200)
    expect(ev.some((e: any) => e.reason?.includes('Contract section 4'))).toBeTruthy()
  })

  test('TC-API-060 AI drafts one narrative section per category, labelled AiDrafted', async ({ request }) => {
    tc({ id: 'TC-API-060', story: 'US-5.1', type: 'API', priority: 'P1', steps: ['POST Narrative/Draft for each active category'], expected: 'One section per category with status AiDrafted and non-empty narrative text' })
    const id = state.need(K('assessmentId'))
    const cats: string[] = state.need(K('activeCats'))
    const out: string[] = []
    for (const c of cats) {
      const r = await call(request, 'POST', '/api/Narrative/Draft', { data: { assessmentId: id, riskCategoryId: c, regenerationFeedback: null }, label: `draft ${c.slice(-1)} (AI)` })
      expect(r.status).toBe(200)
      expect(r.body.data.status).toBe('AiDrafted')
      expect(r.body.data.narrativeText.length).toBeGreaterThan(50)
      out.push(`${r.body.data.categoryName}: ${r.body.data.narrativeText.length} chars in ${r.ms} ms, flags=${r.body.data.unsupportedClaimFlagsJson}`)
    }
    actual(out.join(' | '))
  })

  test('TC-API-061 Finalize is blocked while a section is still AI-drafted', async ({ request }) => {
    tc({ id: 'TC-API-061', story: 'US-5.1 / US-6.3', type: 'Negative', priority: 'P1', steps: ['GET Readiness', 'POST Finalize'], expected: 'Readiness lists every AI-drafted section; Finalize -> 400 naming them' })
    const id = state.need(K('assessmentId'))
    const an = await userId(request, USERS.analyst)
    const ready = await call(request, 'GET', `/api/Assessment/${id}/Readiness`, { label: 'readiness' })
    const fin = await call(request, 'POST', `/api/Assessment/${id}/Finalize`, { data: { actorUserId: an }, label: 'finalize' })
    actual(`outstanding=${JSON.stringify(ready.body.data.outstandingNarrativeSections)}; finalize -> ${fin.status} "${fin.body.message}"`)
    expect(ready.body.data.isReady).toBe(false)
    expect(fin.status).toBe(400)
    expect(fin.body.message).toMatch(/Narrative not yet reviewed/)
  })

  test('TC-API-062 Regenerate one section with feedback; others untouched; prior version kept', async ({ request }) => {
    tc({ id: 'TC-API-062', story: 'US-5.2', type: 'API', priority: 'P2', steps: ['Snapshot all sections', 'POST Narrative/Draft for category #1 with regenerationFeedback', 'Compare sections', 'Check audit for the prior version'], expected: 'Only category #1 text changes; other sections identical; audit retains earlier draft' })
    const id = state.need(K('assessmentId'))
    const crId = state.need(K('crId'))
    const cats: string[] = state.need(K('activeCats'))
    const before = await call(request, 'GET', `/api/Narrative/${id}`, { label: 'before' })
    const r = await call(request, 'POST', '/api/Narrative/Draft', { data: { assessmentId: id, riskCategoryId: cats[0], regenerationFeedback: 'Mention the Malta jurisdiction and cardholder PII explicitly; keep it under 120 words.' }, label: 'regenerate (AI)' })
    const after = await call(request, 'GET', `/api/Narrative/${id}`, { label: 'after' })
    const trail = await call(request, 'GET', `/api/Audit/${crId}`, { label: 'audit' })
    const text = (d: any, c: string) => d.body.data.find((s: any) => s.riskCategoryId === c)?.narrativeText
    expect(r.status).toBe(200)
    expect(text(after, cats[0])).not.toBe(text(before, cats[0]))
    for (const c of cats.slice(1)) expect(text(after, c)).toBe(text(before, c))
    const narrativeEvents = trail.body.data.filter((e: any) => /Narrative/.test(e.entityType))
    actual(`regenerated in ${r.ms} ms; section #1 changed, ${cats.length - 1} other sections unchanged; narrative audit events: ${narrativeEvents.map((e: any) => e.action).join(', ')}`)
    // Prior version retrievable: at least two draft events exist for the regenerated section.
    expect(narrativeEvents.filter((e: any) => /Draft|Regenerat/i.test(e.action)).length).toBeGreaterThanOrEqual(cats.length + 1)
  })

  test('TC-API-063 Narrative edit requires a reason; review/accept sets analyst status', async ({ request }) => {
    tc({ id: 'TC-API-063', story: 'US-6.1', type: 'Negative', priority: 'P1', steps: ['POST Narrative/Edit with empty reason', 'POST Narrative/Edit on category #1 with reason', 'POST Narrative/Review (accept as-is) for the rest', 'GET sections'], expected: 'Blank reason -> 400; edited section = AnalystEdited; accepted sections = AnalystReviewed' })
    const id = state.need(K('assessmentId'))
    const cats: string[] = state.need(K('activeCats'))
    const an = await userId(request, USERS.analyst)
    const noReason = await call(request, 'POST', '/api/Narrative/Edit', { data: { assessmentId: id, riskCategoryId: cats[0], newText: 'Edited by QA', reason: '', actorUserId: an }, label: 'edit no reason' })
    const ed = await call(request, 'POST', '/api/Narrative/Edit', { data: { assessmentId: id, riskCategoryId: cats[0], newText: 'QA analyst narrative: vendor in Malta processes cardholder PII via API; enhanced due diligence and contractual audit rights required.', reason: 'Tightened wording and added EDD requirement', actorUserId: an }, label: 'edit with reason' })
    for (const c of cats.slice(1)) await call(request, 'POST', '/api/Narrative/Review', { data: { assessmentId: id, riskCategoryId: c, actorUserId: an }, label: `accept ${c.slice(-1)}` })
    const s = await call(request, 'GET', `/api/Narrative/${id}`, { label: 'sections' })
    actual(`no reason -> ${noReason.status} "${noReason.body.message}"; edit -> ${ed.status}; statuses: ${s.body.data.map((x: any) => `${x.categoryName}=${x.status}`).join(', ')}`)
    expect(noReason.status).toBe(400)
    expect(s.body.data.find((x: any) => x.riskCategoryId === cats[0]).status).toBe('AnalystEdited')
    for (const c of cats.slice(1)) expect(s.body.data.find((x: any) => x.riskCategoryId === c).status).toBe('AnalystReviewed')
  })

  test('TC-API-070 Residual risk = inherent - (effectiveness x mitigation factor), always > 0', async ({ request }) => {
    tc({ id: 'TC-API-070', story: 'US-7.1', type: 'API', priority: 'P1', steps: ['Scoring/Calculate inherent=4, effectiveness=0.8 on category #1', 'Calculate the extreme case inherent=1, effectiveness=1.0 on category #2', 'GET scores'], expected: 'residual = 4 - 0.8 x mf exactly; extreme case residual still > 0; inherent, mitigation and residual all shown' })
    const id = state.need(K('assessmentId'))
    const cats: string[] = state.need(K('activeCats'))
    const a = await call(request, 'POST', '/api/Scoring/Calculate', { data: { assessmentId: id, riskCategoryId: cats[0], inherentRating: 4, controlIdsCredited: [], controlEffectiveness: 0.8 }, label: 'calc 4/0.8' })
    const b = await call(request, 'POST', '/api/Scoring/Calculate', { data: { assessmentId: id, riskCategoryId: cats[1], inherentRating: 1, controlIdsCredited: [], controlEffectiveness: 1.0 }, label: 'calc 1/1.0 (extreme)' })
    expect(a.status).toBe(200)
    expect(b.status).toBe(200)
    const mf = a.body.data.mitigationFactorApplied
    expect(mf).toBeLessThan(1)
    expect(a.body.data.residualRating).toBeCloseTo(4 - 0.8 * mf, 2)
    expect(b.body.data.residualRating).toBeGreaterThan(0)
    for (const c of cats.slice(2)) await call(request, 'POST', '/api/Scoring/Calculate', { data: { assessmentId: id, riskCategoryId: c, inherentRating: 3, controlIdsCredited: [], controlEffectiveness: 0.5 }, label: `calc ${c.slice(-1)}` })
    state.set(K('mf'), { cat: cats[0], mf })
    actual(`cat#1: 4 - 0.8 x ${mf} = ${a.body.data.residualRating}; extreme 1 - 1.0 x ${b.body.data.mitigationFactorApplied} = ${b.body.data.residualRating} (> 0)`)
  })

  test('TC-API-071 Out-of-range scoring inputs are rejected cleanly', async ({ request }) => {
    tc({ id: 'TC-API-071', story: 'US-7.1', type: 'Negative', priority: 'P2', steps: ['Calculate inherent=0', 'Calculate inherent=6', 'Calculate effectiveness=1.5', 'Calculate effectiveness=-0.2'], expected: 'Each rejected with 400 and a validation message (never a residual <= 0 persisted)' })
    const id = state.need(K('assessmentId'))
    const cats: string[] = state.need(K('activeCats'))
    const cases = [
      { inherentRating: 0, controlEffectiveness: 0.5 },
      { inherentRating: 6, controlEffectiveness: 0.5 },
      { inherentRating: 3, controlEffectiveness: 1.5 },
      { inherentRating: 3, controlEffectiveness: -0.2 },
    ]
    const res: string[] = []
    for (const c of cases) {
      const r = await call(request, 'POST', '/api/Scoring/Calculate', { data: { assessmentId: id, riskCategoryId: cats[0], controlIdsCredited: [], ...c }, label: `inherent ${c.inherentRating} eff ${c.controlEffectiveness}` })
      res.push(`(${c.inherentRating}, ${c.controlEffectiveness}) -> ${r.status} "${r.body.message}"`)
      expect(r.status, 'never accepted').not.toBe(200)
      expect.soft(r.status, 'should be a 400 validation error, not a 500').toBe(400)
    }
    const scores = await call(request, 'GET', `/api/Scoring/${id}`, { label: 'scores unchanged' })
    for (const s of scores.body.data) expect(s.residualRating).toBeGreaterThan(0)
    actual(res.join('; '))
  })

  test('TC-API-072 Score override: reason mandatory, residual must stay > 0, labelled as override', async ({ request }) => {
    tc({ id: 'TC-API-072', story: 'US-7.2', type: 'Negative', priority: 'P1', steps: ['Override residual=2.5 with blank reason', 'Override residual=0 with reason', 'Override residual=-1', 'Override residual=2.5 with reason', 'GET scores + audit'], expected: 'Blank reason / zero / negative -> 400; valid override saved with isOverride=true, scoredBy Analyst, reason; audit keeps the calculated value' })
    const id = state.need(K('assessmentId'))
    const crId = state.need(K('crId'))
    const cats: string[] = state.need(K('activeCats'))
    const an = await userId(request, USERS.analyst)
    const o = (v: number, reason: string, label: string) => call(request, 'POST', '/api/Scoring/Override', { data: { assessmentId: id, riskCategoryId: cats[0], newResidualRating: v, reason, actorUserId: an }, label })
    const a = await o(2.5, '', 'blank reason')
    const b = await o(0, 'zero test', 'zero')
    const c = await o(-1, 'negative test', 'negative')
    const d = await o(2.5, 'Vendor has had two prior regulatory findings', 'valid')
    const s = await call(request, 'GET', `/api/Scoring/${id}`, { label: 'scores' })
    const row = s.body.data.find((x: any) => x.riskCategoryId === cats[0])
    const trail = await call(request, 'GET', `/api/Audit/${crId}`, { label: 'audit' })
    const scoreEv = trail.body.data.filter((e: any) => e.entityType === 'RiskScore').map((e: any) => e.action)
    actual(`blank -> ${a.status}; zero -> ${b.status} "${b.body.message}"; negative -> ${c.status}; valid -> ${d.status}; row: residual ${row.residualRating}, isOverride=${row.isOverride}, scoredBy=${row.scoredBy}, reason="${row.overrideReason}"; RiskScore audit: ${scoreEv.join(', ')}`)
    expect(a.status).toBe(400)
    expect(b.status).toBe(400)
    expect(c.status).toBe(400)
    expect(d.status).toBe(200)
    expect(row.isOverride).toBe(true)
    expect(row.overrideReason).toContain('regulatory findings')
    expect.soft(row.scoredBy, 'an analyst override should be attributed to the Analyst, not System').toBe('Analyst')
    if (row.scoredBy !== 'Analyst') defect('DEF-014')
    expect(scoreEv).toEqual(expect.arrayContaining(['Calculated', 'Overridden']))
  })

  test('TC-API-073 Controls library per category', async ({ request }) => {
    tc({ id: 'TC-API-073', story: 'US-7.1', type: 'API', priority: 'P3', steps: ['GET Scoring/Controls/{categoryId} for each of the 4 categories'], expected: 'Each category has at least one configured control (name + description) so credited controls and their weights are traceable' })
    const out: string[] = []
    let total = 0
    for (const [k, v] of Object.entries(CAT)) {
      const r = await call(request, 'GET', `/api/Scoring/Controls/${v}`, { label: `controls ${k}` })
      expect(r.status).toBe(200)
      out.push(`${k}=${r.body.data.length}`)
      total += r.body.data.length
    }
    actual(`controls per category: ${out.join(', ')}`)
    defect('DEF-013')
    expect(total, 'US-7.1 AC3 needs a controls library to credit and trace').toBeGreaterThan(0)
  })

  test('TC-API-080 Committee vote is rejected before the assessment is routed', async ({ request }) => {
    tc({ id: 'TC-API-080', story: 'US-8.2', type: 'Negative', priority: 'P1', steps: ['POST Committee/Vote on an assessment still InAssessment'], expected: '400 "not in the committee queue ... Route it first"' })
    const id = state.need(K('assessmentId'))
    const cm = await userId(request, USERS.committee1)
    const r = await call(request, 'POST', '/api/Committee/Vote', { data: { assessmentId: id, committeeMemberUserId: cm, vote: 'Approve' } })
    actual(`${r.status} "${r.body.message}"`)
    expect(r.status).toBe(400)
    expect(r.body.message).toMatch(/Route it first/)
  })

  test('TC-API-081 Finalize records the analyst; route puts it in the committee queue', async ({ request }) => {
    tc({ id: 'TC-API-081', story: 'US-6.3 / US-8.1', type: 'API', priority: 'P1', steps: ['GET Readiness (expect ready)', 'POST Finalize as Amara Chen', 'POST Committee/Route', 'GET Committee/Queue and change request status', 'GET audit'], expected: 'Finalize 200; status Finalized; route 200; request appears in queue; CR status PendingCommittee; audit names the finalizing analyst' })
    const id = state.need(K('assessmentId'))
    const crId = state.need(K('crId'))
    const an = await userId(request, USERS.analyst)
    const ready = await call(request, 'GET', `/api/Assessment/${id}/Readiness`, { label: 'readiness' })
    expect(ready.body.data.isReady).toBe(true)
    const fin = await call(request, 'POST', `/api/Assessment/${id}/Finalize`, { data: { actorUserId: an }, label: 'finalize' })
    expect(fin.status).toBe(200)
    const route = await call(request, 'POST', '/api/Committee/Route', { data: { assessmentId: id, actorUserId: an }, label: 'route' })
    expect(route.status).toBe(200)
    const q = await call(request, 'GET', '/api/Committee/Queue', { label: 'queue' })
    const cr = await call(request, 'GET', `/api/ChangeRequest/${crId}`, { label: 'cr' })
    const trail = await call(request, 'GET', `/api/Audit/${crId}`, { label: 'audit' })
    const finEv = trail.body.data.find((e: any) => e.entityType === 'Assessment' && /Finali/.test(e.action))
    actual(`finalize ${fin.status}, route ${route.status}; in queue: ${q.body.data.some((x: any) => x.assessmentId === id)}; CR status ${cr.body.data.status}; finalize audit actor "${finEv?.actorName ?? finEv?.actorLabel}"`)
    expect(q.body.data.some((x: any) => x.assessmentId === id)).toBeTruthy()
    expect(cr.body.data.status).toBe('PendingCommittee')
    expect(finEv?.actorName).toBe(USERS.analyst)
  })

  test('TC-API-082 Edits after finalization are blocked (assessment locked)', async ({ request }) => {
    tc({ id: 'TC-API-082', story: 'US-6.3', type: 'Negative', priority: 'P1', steps: ['After finalize: POST Narrative/Edit', 'POST Scoring/Override', 'POST CategoryMapping/Override', 'POST Finalize again'], expected: 'All rejected - a finalized assessment is locked' })
    defect('DEF-007')
    const id = state.need(K('assessmentId'))
    const cats: string[] = state.need(K('activeCats'))
    const an = await userId(request, USERS.analyst)
    const e = await call(request, 'POST', '/api/Narrative/Edit', { data: { assessmentId: id, riskCategoryId: cats[0], newText: 'post-finalize tamper', reason: 'QA lock test', actorUserId: an }, label: 'narrative edit' })
    const s = await call(request, 'POST', '/api/Scoring/Override', { data: { assessmentId: id, riskCategoryId: cats[0], newResidualRating: 0.5, reason: 'QA lock test', actorUserId: an }, label: 'score override' })
    const m = await call(request, 'POST', '/api/CategoryMapping/Override', { data: { assessmentId: id, riskCategoryId: CAT.products, isActive: true, reason: 'QA lock test', actorUserId: an }, label: 'category add' })
    const f = await call(request, 'POST', `/api/Assessment/${id}/Finalize`, { data: { actorUserId: an }, label: 'finalize again' })
    actual(`narrative edit -> ${e.status}; score override -> ${s.status}; category add -> ${m.status}; re-finalize -> ${f.status}`)
    expect.soft(e.status, 'narrative edit after finalize').not.toBe(200)
    expect.soft(s.status, 'score override after finalize').not.toBe(200)
    expect.soft(m.status, 'category change after finalize').not.toBe(200)
  })

  test('TC-API-083 Vote validation: conditions / rationale mandatory; only committee members may vote', async ({ request }) => {
    tc({ id: 'TC-API-083', story: 'US-8.2', type: 'Negative', priority: 'P1', steps: ['On the routed probe assessment, as Jordan Blake: vote ApproveWithConditions with blank conditions', 'Vote Reject with no rationale', 'Vote Defer with whitespace rationale', 'Vote "Maybe"', 'Vote as the Product Owner (not a committee member)', 'GET votes + decision'], expected: 'Every case rejected with 400/403; no vote recorded for a non-committee user; no decision reached' })
    const id = state.need(K('probeAssessmentId'))
    const cm = await userId(request, USERS.committee1)
    const po = await userId(request, USERS.po)
    const v = (data: any, label: string) => call(request, 'POST', '/api/Committee/Vote', { data: { assessmentId: id, committeeMemberUserId: cm, ...data }, label })
    const a = await v({ vote: 'ApproveWithConditions', conditionsText: '' }, 'AWC blank')
    const b = await v({ vote: 'Reject' }, 'Reject no rationale')
    const c = await v({ vote: 'Defer', rationale: '   ' }, 'Defer blank rationale')
    const d = await v({ vote: 'Maybe' }, 'invalid vote')
    const e = await v({ vote: 'Approve', committeeMemberUserId: po }, 'PO votes')
    const votes = await call(request, 'GET', `/api/Committee/${id}/Votes`, { label: 'votes' })
    const dec = await call(request, 'GET', `/api/Committee/${id}/Decision`, { label: 'decision' })
    actual(`AWC blank -> ${a.status}; Reject none -> ${b.status}; Defer whitespace -> ${c.status}; "Maybe" -> ${d.status} "${d.body.message}"; PO vote -> ${e.status}; recorded votes: ${votes.body.data.map((x: any) => `${x.committeeMemberName}=${x.vote}`).join(', ')}; decision: ${dec.body.data?.resolution ?? 'none'}`)
    defect('DEF-002')
    defect('DEF-030')
    expect.soft(a.status, 'blank conditions').toBe(400)
    expect.soft(b.status).toBe(400)
    expect.soft(c.status, 'whitespace-only rationale').toBe(400)
    expect.soft(d.status).toBe(400)
    expect.soft([400, 403], 'Product Owner must not be able to vote').toContain(e.status)
    expect.soft(dec.status, 'no decision should result from invalid / non-member votes').toBe(404)
  })

  test('TC-API-084 A member vote cannot be silently replaced', async ({ request }) => {
    tc({ id: 'TC-API-084', story: 'US-8.2 / US-9.2', type: 'Negative', priority: 'P2', steps: ['On a second routed probe: Jordan Blake votes Approve', 'Jordan Blake votes again (Reject with rationale)', 'GET votes'], expected: 'Second vote rejected (400/409) - or, if re-voting is allowed, both versions retained; the first vote is never overwritten in place' })
    const po = await userId(request, USERS.po)
    const an = await userId(request, USERS.analyst)
    const cm = await userId(request, USERS.committee1)
    // Needs a routed item with no decision yet; the broken readiness gate (DEF-001) is what makes
    // an empty assessment routable - if that is fixed, this probe is skipped instead.
    const cr = await call(request, 'POST', '/api/ChangeRequest/Submit', { data: { changeType: 'Feature', title: qaTitle('API probe - re-vote'), description: 'x', submittedByUserId: po }, label: 'submit probe 2' })
    const id = (await call(request, 'POST', `/api/Assessment/OpenWorkspace/${cr.body.data.id}`, { label: 'open' })).body.data
    await call(request, 'POST', `/api/Assessment/${id}/Finalize`, { data: { actorUserId: an }, label: 'finalize' })
    const routed = await call(request, 'POST', '/api/Committee/Route', { data: { assessmentId: id, actorUserId: an }, label: 'route' })
    test.skip(routed.status !== 200, 'Empty assessments can no longer be routed (DEF-001 fixed) - probe needs a fully prepared item')
    const v1 = await call(request, 'POST', '/api/Committee/Vote', { data: { assessmentId: id, committeeMemberUserId: cm, vote: 'Approve' }, label: 'first vote' })
    const v2 = await call(request, 'POST', '/api/Committee/Vote', { data: { assessmentId: id, committeeMemberUserId: cm, vote: 'Reject', rationale: 'changed my mind' }, label: 'second vote' })
    const votes = await call(request, 'GET', `/api/Committee/${id}/Votes`, { label: 'votes' })
    const trail = await call(request, 'GET', `/api/Audit/${cr.body.data.id}`, { label: 'audit' })
    const voteEvents = trail.body.data.filter((e: any) => /Vote/i.test(e.entityType))
    actual(`first -> ${v1.status} id ${v1.body.data}; second -> ${v2.status} id ${v2.body.data} (${v1.body.data === v2.body.data ? 'SAME row - overwritten' : 'new row'}); votes table now: ${votes.body.data.map((x: any) => `${x.committeeMemberName}=${x.vote}`).join(', ')}; vote audit events: ${voteEvents.length}`)
    defect('DEF-003')
    expect.soft([400, 409], 're-vote should be rejected').toContain(v2.status)
    expect(votes.body.data.find((x: any) => x.committeeMemberName === USERS.committee1)?.vote, 'first vote must not be overwritten').toBe('Approve')
  })

  test('TC-API-085 Individual votes recorded; quorum resolves the decision conservatively', async ({ request }) => {
    tc({ id: 'TC-API-085', story: 'US-8.2 / US-8.3', type: 'API', priority: 'P1', steps: ['Jordan Blake votes ApproveWithConditions with conditions', 'Riley Voss votes Approve (quorum = 2)', 'GET votes, decision, change request', 'Late vote after decision'], expected: 'Each vote stored with member name; decision ApprovedWithConditions carrying the conditions; CR status Decisioned; late vote rejected' })
    const id = state.need(K('assessmentId'))
    const crId = state.need(K('crId'))
    const c1 = await userId(request, USERS.committee1)
    const c2 = await userId(request, USERS.committee2)
    const v1 = await call(request, 'POST', '/api/Committee/Vote', { data: { assessmentId: id, committeeMemberUserId: c1, vote: 'ApproveWithConditions', conditionsText: 'Annual on-site audit of the vendor; PII encrypted at rest' }, label: 'vote 1 AWC' })
    const v2 = await call(request, 'POST', '/api/Committee/Vote', { data: { assessmentId: id, committeeMemberUserId: c2, vote: 'Approve' }, label: 'vote 2 Approve' })
    const votes = await call(request, 'GET', `/api/Committee/${id}/Votes`, { label: 'votes' })
    const dec = await call(request, 'GET', `/api/Committee/${id}/Decision`, { label: 'decision' })
    const cr = await call(request, 'GET', `/api/ChangeRequest/${crId}`, { label: 'cr' })
    const late = await call(request, 'POST', '/api/Committee/Vote', { data: { assessmentId: id, committeeMemberUserId: c2, vote: 'Reject', rationale: 'late' }, label: 'late vote' })
    actual(`vote1 ${v1.status}; vote2 ${v2.status}; votes: ${votes.body.data.map((x: any) => `${x.committeeMemberName}=${x.vote}`).join(', ')}; decision ${dec.body.data?.resolution} "${dec.body.data?.conditionsText}"; CR ${cr.body.data.status}; late vote -> ${late.status}`)
    expect(v1.status).toBe(200)
    expect(v2.status).toBe(200)
    expect(votes.body.data.map((x: any) => x.committeeMemberName).sort()).toEqual([USERS.committee1, USERS.committee2].sort())
    expect(dec.body.data.resolution).toBe('ApprovedWithConditions')
    expect(dec.body.data.conditionsText).toContain('Annual on-site audit')
    expect(cr.body.data.status).toBe('Decisioned')
    expect(late.status).toBe(400)
  })

  test('TC-API-090 Audit trail reconstructs the full history in order', async ({ request }) => {
    tc({ id: 'TC-API-090', story: 'US-9.1', type: 'API', priority: 'P1', steps: ['GET /api/Audit/{crId}'], expected: 'Chronological events covering submission, upload, AI outputs, overrides with reasons, reliance, scores, finalize, route, each vote, decision; actor shown as a person or system/AI' })
    const crId = state.need(K('crId'))
    const r = await call(request, 'GET', `/api/Audit/${crId}`, { label: 'audit trail' })
    const ev = r.body.data
    const ts = ev.map((e: any) => Date.parse(e.createdAt))
    expect([...ts].sort((a, b) => a - b)).toEqual(ts)
    const kinds = new Set(ev.map((e: any) => e.entityType))
    for (const k of ['ChangeRequest', 'Attachment', 'RiskScore', 'Assessment']) expect(kinds).toContain(k)
    const joined = ev.map((e: any) => `${e.entityType}.${e.action}`).join(',')
    expect(joined).toMatch(/Vote/i)
    expect(joined).toMatch(/Decision/i)
    for (const e of ev) expect(e.actorName || e.actorLabel).toBeTruthy()
    actual(`${ev.length} events, chronological; entity types: ${[...kinds].join(', ')}`)
  })

  test('TC-API-091 Audit records cannot be modified or deleted through the API', async ({ request }) => {
    tc({ id: 'TC-API-091', story: 'US-9.2', type: 'Security', priority: 'P1', steps: ['PUT /api/Audit/{crId}', 'DELETE /api/Audit/{crId}', 'PATCH /api/Audit/{crId}', 'GET trail again'], expected: 'No write verbs exposed (404/405); trail unchanged' })
    const crId = state.need(K('crId'))
    const before = await call(request, 'GET', `/api/Audit/${crId}`, { label: 'before' })
    const put = await call(request, 'PUT', `/api/Audit/${crId}`, { data: { reason: 'tamper' }, label: 'PUT' })
    const del = await call(request, 'DELETE', `/api/Audit/${crId}`, { label: 'DELETE' })
    const patch = await call(request, 'PATCH', `/api/Audit/${crId}`, { data: { reason: 'tamper' }, label: 'PATCH' })
    const after = await call(request, 'GET', `/api/Audit/${crId}`, { label: 'after' })
    actual(`PUT ${put.status}, DELETE ${del.status}, PATCH ${patch.status}; events before=${before.body.data.length} after=${after.body.data.length}`)
    for (const s of [put.status, del.status, patch.status]) expect([404, 405]).toContain(s)
    expect(after.body.data.length).toBe(before.body.data.length)
  })
})
