import { expect, test } from '@playwright/test'
import { actual, call, defect, qaTitle, tc } from '../../lib/harness'
import { userId, USERS } from '../../lib/app'

const CUSTOMERS = '22222222-2222-2222-2222-222222222222'
// Observed live value for Customers & Entities (TC-API-070). Positive config tests write this same
// value back so the shared dev environment ends each run exactly as it started.
const BASELINE_MF = 0.85

test.describe('Epic 10 - Platform configuration', () => {
  test('TC-API-100 Mitigation factor >= 1.0 (or < 0) is rejected at configuration time', async ({ request }) => {
    tc({ id: 'TC-API-100', story: 'US-10.1', type: 'Negative', priority: 'P1', steps: ['POST Scoring/Config maxMitigationFactor=1.0', '... =1.5', '... =-0.1', '... =0.999'], expected: '1.0 / 1.5 / -0.1 rejected with 400 and an explicit "residual risk would reach zero" message; 0.999 is the largest accepted value class' })
    const admin = await userId(request, USERS.admin)
    const res: string[] = []
    for (const v of [1.0, 1.5, -0.1]) {
      const r = await call(request, 'POST', '/api/Scoring/Config', { data: { riskCategoryId: CUSTOMERS, maxMitigationFactor: v, reason: 'QA boundary test', actorUserId: admin }, label: `mf ${v}` })
      res.push(`${v} -> ${r.status} "${r.body.message}"`)
      expect(r.status).toBe(400)
      expect(r.body.message).toMatch(/residual risk reach zero/)
    }
    actual(res.join('; '))
  })

  test('TC-API-101 Scoring configuration change requires a reason', async ({ request }) => {
    tc({ id: 'TC-API-101', story: 'US-10.1', type: 'Negative', priority: 'P1', steps: [`POST Scoring/Config maxMitigationFactor=${BASELINE_MF} (unchanged) with blank reason`], expected: '400 - reason is mandatory' })
    const admin = await userId(request, USERS.admin)
    const r = await call(request, 'POST', '/api/Scoring/Config', { data: { riskCategoryId: CUSTOMERS, maxMitigationFactor: BASELINE_MF, reason: '', actorUserId: admin } })
    actual(`${r.status} "${r.body.message ?? r.body.data}"`)
    defect(r.status === 200 ? 'DEF-009' : 'DEF-005')
    expect(r.status).toBe(400)
  })

  test('TC-API-102 Config change applies only to assessments started afterwards', async ({ request }) => {
    tc({ id: 'TC-API-102', story: 'US-10.1', type: 'API', priority: 'P2', steps: ['Open a probe assessment (config at baseline)', 'Change Customers & Entities cap to 0.80 (reason given)', 'Calculate a score on the probe assessment', 'Restore the cap to the baseline'], expected: `The in-flight probe still uses the cap in force when it started (${BASELINE_MF}), not 0.80` })
    const po = await userId(request, USERS.po)
    const admin = await userId(request, USERS.admin)
    const cr = await call(request, 'POST', '/api/ChangeRequest/Submit', { data: { changeType: 'CustomerSegment', title: qaTitle('API probe - config versioning'), description: 'x', submittedByUserId: po }, label: 'submit probe' })
    const assessmentId = (await call(request, 'POST', `/api/Assessment/OpenWorkspace/${cr.body.data.id}`, { label: 'open' })).body.data
    try {
      const change = await call(request, 'POST', '/api/Scoring/Config', { data: { riskCategoryId: CUSTOMERS, maxMitigationFactor: 0.8, reason: 'QA: in-flight isolation test (restored immediately)', actorUserId: admin }, label: 'set 0.80' })
      expect(change.status).toBe(200)
      const s = await call(request, 'POST', '/api/Scoring/Calculate', { data: { assessmentId, riskCategoryId: CUSTOMERS, inherentRating: 3, controlIdsCredited: [], controlEffectiveness: 1 }, label: 'calculate on in-flight' })
      actual(`probe started at ${BASELINE_MF}; after change to 0.80 the in-flight calc used mf=${s.body.data?.mitigationFactorApplied} (residual ${s.body.data?.residualRating})`)
      defect('DEF-016')
      expect(s.body.data.mitigationFactorApplied).toBe(BASELINE_MF)
    } finally {
      await call(request, 'POST', '/api/Scoring/Config', { data: { riskCategoryId: CUSTOMERS, maxMitigationFactor: BASELINE_MF, reason: 'QA: restore baseline after TC-API-102', actorUserId: admin }, label: 'restore baseline' })
    }
  })

  test('TC-API-103 Workflow rules: listed in plain form; reason mandatory; invalid JSON rejected', async ({ request }) => {
    tc({ id: 'TC-API-103', story: 'US-10.2', type: 'Negative', priority: 'P1', steps: ['GET /api/WorkflowRule', 'POST CommitteeQuorum with blank reason', 'POST CommitteeQuorum with value "{not json"', 'POST CommitteeQuorum {"quorum": 2} (unchanged) with reason'], expected: 'Rules readable (key + JSON value); blank reason -> 400; invalid JSON -> 400; valid save -> 200' })
    const admin = await userId(request, USERS.admin)
    const list = await call(request, 'GET', '/api/WorkflowRule', { label: 'rules' })
    const quorum = list.body.data.find((r: any) => r.ruleKey === 'CommitteeQuorum')
    expect(quorum).toBeTruthy()
    const blank = await call(request, 'POST', '/api/WorkflowRule', { data: { ruleKey: 'CommitteeQuorum', ruleValueJson: quorum.ruleValueJson, reason: ' ', actorUserId: admin }, label: 'blank reason' })
    const badJson = await call(request, 'POST', '/api/WorkflowRule', { data: { ruleKey: 'CommitteeQuorum', ruleValueJson: '{not json', reason: 'QA invalid JSON test', actorUserId: admin }, label: 'invalid json' })
    const ok = await call(request, 'POST', '/api/WorkflowRule', { data: { ruleKey: 'CommitteeQuorum', ruleValueJson: quorum.ruleValueJson, reason: 'QA: re-save unchanged value', actorUserId: admin }, label: 'valid (unchanged)' })
    const after = await call(request, 'GET', '/api/WorkflowRule', { label: 'rules after' })
    actual(`rules: ${list.body.data.map((r: any) => `${r.ruleKey}=${r.ruleValueJson}`).join(', ')}; blank reason -> ${blank.status} "${blank.body.message}"; invalid JSON -> ${badJson.status} "${badJson.body.message}"; valid -> ${ok.status}; quorum now ${after.body.data.find((r: any) => r.ruleKey === 'CommitteeQuorum')?.ruleValueJson}`)
    expect(blank.status).toBe(400)
    expect.soft(badJson.status, 'invalid JSON should be a 400, not a 500').toBe(400)
    if (badJson.status !== 400) defect('DEF-005')
    expect(ok.status).toBe(200)
  })
})

test.describe('Security', () => {
  const PROTECTED = ['/api/User', '/api/ChangeRequest', '/api/Committee/Queue', '/api/WorkflowRule', '/api/CategoryMapping/Categories', '/api/DataIngestion/MockCustomers']

  test('TC-SEC-001 Protected endpoints require authentication', async ({ request }) => {
    tc({ id: 'TC-SEC-001', story: 'NFR-SEC', type: 'Security', priority: 'P1', steps: PROTECTED.map((p) => `GET ${p} with no Authorization header`), expected: 'Every [Authorize] endpoint returns 401 to an anonymous caller' })
    defect('DEF-010')
    const res: string[] = []
    for (const p of PROTECTED) {
      const r = await call(request, 'GET', p, { label: `anon ${p}` })
      res.push(`${p}=${r.status}`)
      expect.soft(r.status, p).toBe(401)
    }
    actual(`anonymous access: ${res.join(', ')} (includes user e-mails and all change requests)`)
  })

  test('TC-SEC-002 A forged bearer token is rejected', async ({ request }) => {
    tc({ id: 'TC-SEC-002', story: 'NFR-SEC', type: 'Security', priority: 'P1', steps: ['GET /api/User with "Authorization: Bearer forged.jwt.token"'], expected: '401 invalid_token' })
    defect('DEF-010')
    const r = await call(request, 'GET', '/api/User', { headers: { Authorization: 'Bearer eyJhbGciOiJub25lIn0.eyJzdWIiOiJhdHRhY2tlciJ9.' } })
    actual(`${r.status}`)
    expect(r.status).toBe(401)
  })

  test('TC-SEC-003 Server-side role enforcement - actor ids cannot be spoofed', async ({ request }) => {
    tc({ id: 'TC-SEC-003', story: 'NFR-SEC / US-6.3 / US-10.1', type: 'Security', priority: 'P1', steps: ['Finalize a probe assessment with actorUserId = Product Owner', 'Save scoring config (unchanged value) with actorUserId = Product Owner', 'GET audit to see who is recorded'], expected: 'Both rejected with 403 - only Analysts finalize, only Admin/Analyst configure; the acting user comes from the token, not the request body' })
    defect('DEF-002')
    const po = await userId(request, USERS.po)
    const cr = await call(request, 'POST', '/api/ChangeRequest/Submit', { data: { changeType: 'Process', title: qaTitle('API probe - actor spoofing'), description: 'x', submittedByUserId: po }, label: 'submit probe' })
    const id = (await call(request, 'POST', `/api/Assessment/OpenWorkspace/${cr.body.data.id}`, { label: 'open' })).body.data
    const fin = await call(request, 'POST', `/api/Assessment/${id}/Finalize`, { data: { actorUserId: po }, label: 'finalize as PO' })
    const cfg = await call(request, 'POST', '/api/Scoring/Config', { data: { riskCategoryId: CUSTOMERS, maxMitigationFactor: BASELINE_MF, reason: 'QA: RBAC probe - value unchanged', actorUserId: po }, label: 'config as PO' })
    const trail = await call(request, 'GET', `/api/Audit/${cr.body.data.id}`, { label: 'audit' })
    const finEv = trail.body.data.find((e: any) => e.entityType === 'Assessment' && /Finali/.test(e.action))
    actual(`finalize as Product Owner -> ${fin.status} (audit records finalizer "${finEv?.actorName ?? '-'}"); scoring config as Product Owner -> ${cfg.status}`)
    expect.soft(fin.status).toBe(403)
    expect.soft(cfg.status).toBe(403)
  })

  test('TC-SEC-004 API specification is not publicly exposed in the deployed environment', async ({ request }) => {
    tc({ id: 'TC-SEC-004', story: 'NFR-SEC', type: 'Security', priority: 'P2', steps: ['GET /openapi/v1.json'], expected: '404 - OpenAPI is mapped only in Development; the deployed app should not run as Development' })
    defect('DEF-010')
    const r = await call(request, 'GET', '/openapi/v1.json')
    const paths = typeof r.body === 'object' ? Object.keys((r.body as any).paths || {}).length : 0
    actual(`${r.status}; ${paths} API paths disclosed`)
    expect(r.status).toBe(404)
  })

  test('TC-SEC-005 Security response headers', async ({ request }) => {
    tc({ id: 'TC-SEC-005', story: 'NFR-SEC', type: 'Security', priority: 'P2', steps: ['GET / and GET /api/Ping', 'Inspect response headers'], expected: 'Strict-Transport-Security, Content-Security-Policy, X-Content-Type-Options: nosniff, X-Frame-Options/frame-ancestors and Referrer-Policy present; no Server banner' })
    defect('DEF-017')
    const r = await call(request, 'GET', '/')
    const h = r.headers
    const want = ['strict-transport-security', 'content-security-policy', 'x-content-type-options', 'x-frame-options', 'referrer-policy']
    const missing = want.filter((k) => !h[k])
    actual(`missing: ${missing.join(', ') || 'none'}; server: "${h['server'] ?? ''}"`)
    for (const k of want) expect.soft(h[k], k).toBeTruthy()
    expect.soft(h['server'], 'server banner').toBeFalsy()
  })

  test('TC-SEC-006 CORS does not trust arbitrary origins', async ({ request }) => {
    tc({ id: 'TC-SEC-006', story: 'NFR-SEC', type: 'Security', priority: 'P1', steps: ['OPTIONS /api/ChangeRequest/Submit with Origin: https://evil.example and Access-Control-Request-Method: POST'], expected: 'No Access-Control-Allow-Origin for the foreign origin' })
    defect('DEF-019')
    const r = await call(request, 'GET', '/api/Ping', { headers: { Origin: 'https://evil.example' }, label: 'GET with foreign origin' })
    const pre = await request.fetch('/api/ChangeRequest/Submit', { method: 'OPTIONS', headers: { Origin: 'https://evil.example', 'Access-Control-Request-Method': 'POST' }, failOnStatusCode: false })
    actual(`GET ACAO="${r.headers['access-control-allow-origin'] ?? ''}"; preflight ${pre.status()} ACAO="${pre.headers()['access-control-allow-origin'] ?? ''}"`)
    expect(r.headers['access-control-allow-origin']).toBeUndefined()
    expect(pre.headers()['access-control-allow-origin']).toBeUndefined()
  })

  test('TC-SEC-007 Error responses do not leak internals', async ({ request }) => {
    tc({ id: 'TC-SEC-007', story: 'NFR-SEC', type: 'Security', priority: 'P3', steps: ['POST Submit with malformed JSON', 'POST Scoring/Calculate with an unknown assessment id', 'POST Narrative/Edit with blank reason'], expected: 'Generic messages - no stack traces, SQL, Npgsql/PL-pgSQL error codes or table names' })
    const a = await request.fetch('/api/ChangeRequest/Submit', { method: 'POST', headers: { 'Content-Type': 'application/json' }, data: '{"title": ', failOnStatusCode: false })
    const aText = await a.text()
    const b = await call(request, 'POST', '/api/Scoring/Calculate', { data: { assessmentId: '00000000-0000-0000-0000-00000000dead', riskCategoryId: CUSTOMERS, inherentRating: 3, controlIdsCredited: [], controlEffectiveness: 0.5 }, label: 'unknown assessment' })
    const c = await call(request, 'POST', '/api/Narrative/Edit', { data: { assessmentId: '00000000-0000-0000-0000-00000000dead', riskCategoryId: CUSTOMERS, newText: 'x', reason: '', actorUserId: '00000000-0000-0000-0000-000000000000' }, label: 'blank reason' })
    const all = `${aText} ${JSON.stringify(b.body)} ${JSON.stringify(c.body)}`
    const leaks = ['   at ', 'Npgsql', 'P0001', 'SQLSTATE', 'plpgsql', 'Exception'].filter((s) => all.includes(s))
    actual(`malformed JSON -> ${a.status()}; unknown assessment -> ${b.status} "${b.body.message}"; blank reason -> ${c.status} "${c.body.message}"; leak markers found: ${leaks.join(', ') || 'none'}`)
    expect(a.status()).toBe(400)
    expect.soft(leaks, 'internal error codes in user-facing messages').toEqual([])
    if (leaks.length) defect('DEF-018')
  })

  test('TC-SEC-008 Uploaded documents are not publicly readable from blob storage', async ({ request }) => {
    tc({ id: 'TC-SEC-008', story: 'NFR-SEC / US-1.2', type: 'Security', priority: 'P1', steps: ['Read a storagePath from an attachment list', 'GET it anonymously', 'List the container anonymously'], expected: '403/404 - documents are private' })
    const all = await call(request, 'GET', '/api/ChangeRequest', { label: 'list' })
    let blobUrl = ''
    for (const r of all.body.data.slice(0, 15)) {
      const a = await request.get(`/api/ChangeRequest/${r.id}/Attachments`)
      const hit = (await a.json()).data.find((x: any) => x.storagePath.startsWith('https://'))
      if (hit) {
        blobUrl = hit.storagePath
        break
      }
    }
    test.skip(!blobUrl, 'No blob-backed attachment found')
    const get = await request.fetch(blobUrl, { failOnStatusCode: false })
    const list = await request.fetch(blobUrl.replace(/\/[^/]+$/, '') + '?restype=container&comp=list', { failOnStatusCode: false })
    actual(`blob GET ${get.status()}, container list ${list.status()} (storage account name is disclosed in API responses)`)
    expect([403, 404, 409]).toContain(get.status())
    expect([403, 404, 409]).toContain(list.status())
  })

  test('TC-SEC-009 HTTP is redirected to HTTPS', async ({ playwright }) => {
    tc({ id: 'TC-SEC-009', story: 'NFR-SEC', type: 'Security', priority: 'P2', steps: ['GET http://<host>/ without following redirects'], expected: '301/302/307/308 to https://' })
    const ctx = await playwright.request.newContext()
    const host = new URL(test.info().project.use.baseURL!).host
    const r = await ctx.fetch(`http://${host}/`, { maxRedirects: 0, failOnStatusCode: false })
    actual(`${r.status()} -> ${r.headers()['location'] ?? '(no redirect)'}`)
    expect([301, 302, 307, 308]).toContain(r.status())
    expect(r.headers()['location']).toMatch(/^https:/)
    await ctx.dispose()
  })

  test('TC-SEC-010 Input length limits on free-text fields', async ({ request }) => {
    tc({ id: 'TC-SEC-010', story: 'NFR-SEC / US-1.1', type: 'Security', priority: 'P3', steps: ['Submit a change request with a 20,000-character title'], expected: '400 - title length is bounded' })
    const po = await userId(request, USERS.po)
    const r = await call(request, 'POST', '/api/ChangeRequest/Submit', { data: { changeType: 'Feature', title: qaTitle('long ') + 'A'.repeat(20_000), description: 'x', submittedByUserId: po }, label: 'huge title' })
    actual(`${r.status} ${r.body?.data?.requestNumber ?? r.body?.message ?? ''}`)
    if (r.status === 200) defect('DEF-009')
    expect(r.status).toBe(400)
  })
})
