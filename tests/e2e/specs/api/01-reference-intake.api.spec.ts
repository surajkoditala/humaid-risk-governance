import fs from 'node:fs'
import path from 'node:path'
import { expect, test } from '@playwright/test'
import { actual, call, defect, FIXTURES, qaTitle, tc } from '../../lib/harness'
import { userId, USERS } from '../../lib/app'

const CHANGE_TYPES = ['Product', 'Feature', 'Process', 'Vendor', 'Geography', 'CustomerSegment']

test.describe('Reference data & health', () => {
  test('TC-API-001 Health check endpoint responds', async ({ request }) => {
    tc({ id: 'TC-API-001', story: 'NFR-OPS', type: 'API', priority: 'P1', steps: ['GET /api/Ping'], expected: '200 with data "pong" in the OperationResult envelope' })
    const r = await call(request, 'GET', '/api/Ping')
    expect(r.status).toBe(200)
    expect(r.body.data).toBe('pong')
    actual(`${r.status} "${r.body.data}" in ${r.ms} ms`)
  })

  test('TC-API-002 Seeded users cover all four roles', async ({ request }) => {
    tc({ id: 'TC-API-002', story: 'Roles', type: 'API', priority: 'P2', steps: ['GET /api/User'], expected: 'Users exist for ProductOwner, Analyst, CommitteeMember and Admin' })
    const r = await call(request, 'GET', '/api/User')
    expect(r.status).toBe(200)
    const roles = new Set(r.body.data.map((u: any) => u.role))
    for (const role of ['ProductOwner', 'Analyst', 'CommitteeMember', 'Admin']) expect(roles).toContain(role)
    actual(`${r.body.data.length} users; roles = ${[...roles].join(', ')}`)
  })

  test('TC-API-003 Risk categories are exactly the four FFIEC categories, each citable', async ({ request }) => {
    tc({ id: 'TC-API-003', story: 'US-2.1', type: 'API', priority: 'P1', steps: ['GET /api/CategoryMapping/Categories'], expected: '4 categories (Products & Services, Customers & Entities, Geographic Locations, Delivery Channels) each with an FFIEC citation' })
    const r = await call(request, 'GET', '/api/CategoryMapping/Categories')
    expect(r.status).toBe(200)
    const names = r.body.data.map((c: any) => c.name).sort()
    expect(names).toEqual(['Customers & Entities', 'Delivery Channels', 'Geographic Locations', 'Products & Services'])
    for (const c of r.body.data) expect(c.citationSection).toMatch(/FFIEC BSA\/AML Manual/)
    actual(`Categories: ${names.join(' | ')}; all cite FFIEC BSA/AML Manual`)
  })

  test('TC-API-004 Mock-systems lookups (CRM / core banking / vendor mgmt) return synthetic data', async ({ request }) => {
    tc({ id: 'TC-API-004', story: 'Data-Ingestion', type: 'API', priority: 'P2', steps: ['GET /api/DataIngestion/MockCustomers', 'GET .../MockProducts', 'GET .../MockVendors'], expected: 'Each lookup returns a non-empty id/label list' })
    const counts: string[] = []
    for (const kind of ['MockCustomers', 'MockProducts', 'MockVendors']) {
      const r = await call(request, 'GET', `/api/DataIngestion/${kind}`)
      expect(r.status).toBe(200)
      expect(r.body.data.length).toBeGreaterThan(0)
      expect(r.body.data[0]).toHaveProperty('label')
      counts.push(`${kind}=${r.body.data.length}`)
    }
    actual(counts.join(', '))
  })
})

test.describe('Epic 1 - Change request intake', () => {
  test('TC-API-010 Submit a valid change request', async ({ request }) => {
    tc({ id: 'TC-API-010', story: 'US-1.1', type: 'API', priority: 'P1', steps: ['POST /api/ChangeRequest/Submit with type Product, title, description, PO user id, linked mock product'], expected: '200; unique request number CR-YYYY-NNNNN; status "Submitted"; submittedAt timestamp' })
    const po = await userId(request, USERS.po)
    const r = await call(request, 'POST', '/api/ChangeRequest/Submit', {
      data: { changeType: 'Product', title: qaTitle('API intake - prepaid card'), description: 'Synthetic QA request', typeSpecificFieldsJson: '{"details":"US only"}', submittedByUserId: po, mockProductId: 'b2222222-0000-0000-0000-000000000003' },
    })
    expect(r.status).toBe(200)
    expect(r.body.data.requestNumber).toMatch(/^CR-\d{4}-\d{5}$/)
    expect(r.body.data.status).toBe('Submitted')
    expect(Date.parse(r.body.data.submittedAt)).not.toBeNaN()
    actual(`${r.body.data.requestNumber}, status ${r.body.data.status}, submittedAt ${r.body.data.submittedAt}`)
  })

  test('TC-API-011 Every one of the six change types is accepted', async ({ request }) => {
    tc({ id: 'TC-API-011', story: 'US-1.1', type: 'API', priority: 'P2', steps: CHANGE_TYPES.map((t) => `Submit with changeType=${t}`), expected: 'All six types accepted (200)' })
    const po = await userId(request, USERS.po)
    const seen: string[] = []
    for (const changeType of CHANGE_TYPES) {
      const r = await call(request, 'POST', '/api/ChangeRequest/Submit', {
        data: { changeType, title: qaTitle(`type ${changeType}`), description: 'Synthetic', typeSpecificFieldsJson: '{}', submittedByUserId: po },
        label: `submit ${changeType}`,
      })
      expect.soft(r.status, changeType).toBe(200)
      seen.push(`${changeType}=${r.status}`)
    }
    actual(seen.join(', '))
  })

  test('TC-API-012 Request numbers are unique', async ({ request }) => {
    tc({ id: 'TC-API-012', story: 'US-1.1', type: 'API', priority: 'P1', steps: ['GET /api/ChangeRequest (all)', 'Compare request numbers'], expected: 'No duplicate request numbers' })
    const r = await call(request, 'GET', '/api/ChangeRequest')
    const nums = r.body.data.map((x: any) => x.requestNumber)
    expect(new Set(nums).size).toBe(nums.length)
    actual(`${nums.length} requests, ${new Set(nums).size} distinct numbers`)
  })

  test('TC-API-013 Submission with missing mandatory fields is rejected', async ({ request }) => {
    tc({ id: 'TC-API-013', story: 'US-1.1', type: 'Negative', priority: 'P1', steps: ['POST Submit with empty title and description', 'POST Submit with empty changeType'], expected: '400 Bad Request listing the missing fields; nothing persisted' })
    defect('DEF-009')
    defect('DEF-005')
    const po = await userId(request, USERS.po)
    const a = await call(request, 'POST', '/api/ChangeRequest/Submit', { data: { changeType: 'Product', title: '', description: '', submittedByUserId: po }, label: 'empty title+description' })
    const b = await call(request, 'POST', '/api/ChangeRequest/Submit', { data: { changeType: '', title: qaTitle('no type'), description: 'x', submittedByUserId: po }, label: 'empty changeType' })
    actual(`empty title/description -> ${a.status} ${a.body?.data?.requestNumber ?? a.body?.message ?? ''}; empty changeType -> ${b.status} ${b.body?.data?.requestNumber ?? b.body?.message ?? ''}`)
    expect.soft(a.status).toBe(400)
    expect.soft(b.status).toBe(400)
  })

  test('TC-API-014 Unknown change type is rejected', async ({ request }) => {
    tc({ id: 'TC-API-014', story: 'US-1.1', type: 'Negative', priority: 'P2', steps: ['POST Submit with changeType="Crypto"'], expected: '400 - only the six defined change types are allowed' })
    defect('DEF-005')
    const po = await userId(request, USERS.po)
    const r = await call(request, 'POST', '/api/ChangeRequest/Submit', { data: { changeType: 'Crypto', title: qaTitle('bad type'), description: 'x', submittedByUserId: po } })
    actual(`${r.status} ${r.body?.message ?? r.body?.data?.requestNumber ?? ''}`)
    expect(r.status).toBe(400)
  })

  test('TC-API-015 Get change request by id; unknown id returns 404', async ({ request }) => {
    tc({ id: 'TC-API-015', story: 'US-1.3', type: 'API', priority: 'P2', steps: ['GET /api/ChangeRequest/{existing id}', 'GET /api/ChangeRequest/{random guid}', 'GET /api/ChangeRequest/not-a-guid'], expected: '200 with record; 404 for unknown guid; 404 for malformed id (route constraint)' })
    const all = await call(request, 'GET', '/api/ChangeRequest', { label: 'list' })
    const id = all.body.data[0].id
    const ok = await call(request, 'GET', `/api/ChangeRequest/${id}`)
    const missing = await call(request, 'GET', '/api/ChangeRequest/00000000-0000-0000-0000-000000000abc')
    const bad = await call(request, 'GET', '/api/ChangeRequest/not-a-guid')
    expect(ok.status).toBe(200)
    expect(ok.body.data.id).toBe(id)
    expect(missing.status).toBe(404)
    expect(bad.status).toBe(404)
    actual(`existing=${ok.status}, unknown=${missing.status} "${missing.body.message}", malformed=${bad.status}`)
  })

  test('TC-API-016 "My requests" returns only the requesting user\'s items with days elapsed', async ({ request }) => {
    tc({ id: 'TC-API-016', story: 'US-1.3', type: 'API', priority: 'P2', steps: ['GET /api/ChangeRequest/ForUser/{PO id}', 'GET /api/ChangeRequest/ForUser/{Analyst id}'], expected: 'PO list contains the QA requests with status and daysElapsed; analyst (never submitted) gets an empty list' })
    const po = await userId(request, USERS.po)
    const an = await userId(request, USERS.analyst)
    const mine = await call(request, 'GET', `/api/ChangeRequest/ForUser/${po}`, { label: 'PO requests' })
    const theirs = await call(request, 'GET', `/api/ChangeRequest/ForUser/${an}`, { label: 'Analyst requests' })
    expect(mine.body.data.some((r: any) => r.title.includes('[QA-E2E'))).toBeTruthy()
    for (const r of mine.body.data) {
      expect(r).toHaveProperty('status')
      expect(typeof r.daysElapsed).toBe('number')
    }
    expect(theirs.body.data.length).toBe(0)
    actual(`PO has ${mine.body.data.length} requests; analyst has ${theirs.body.data.length}`)
  })

  test('TC-API-017 Attach PDF, DOCX and XLSX; re-upload creates a new version', async ({ request }) => {
    tc({ id: 'TC-API-017', story: 'US-1.2', type: 'API', priority: 'P1', steps: ['Submit a Vendor request', 'POST AttachDocumentFile with a PDF', 'POST with a DOCX and an XLSX', 'POST PDF again with supersedesAttachmentId', 'GET /{id}/Attachments'], expected: 'All three formats accepted; the replacement is version 2 and version 1 is still listed (not overwritten)' })
    const po = await userId(request, USERS.po)
    const cr = await call(request, 'POST', '/api/ChangeRequest/Submit', { data: { changeType: 'Vendor', title: qaTitle('attachments'), description: 'x', submittedByUserId: po }, label: 'submit' })
    const crId = cr.body.data.id
    const upload = (file: string, mime: string, supersedes?: string) =>
      call(request, 'POST', '/api/ChangeRequest/AttachDocumentFile', {
        multipart: { changeRequestId: crId, uploadedByUserId: po, ...(supersedes ? { supersedesAttachmentId: supersedes } : {}), file: { name: file, mimeType: mime, buffer: fs.readFileSync(path.join(FIXTURES, file)) } },
        label: `upload ${file}${supersedes ? ' (replacement)' : ''}`,
      })
    const pdf = await upload('vendor-due-diligence.pdf', 'application/pdf')
    const docx = await upload('product-spec.docx', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document')
    const xlsx = await upload('control-matrix.xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
    expect(pdf.status).toBe(200)
    expect(docx.status).toBe(200)
    expect(xlsx.status).toBe(200)
    const v2 = await upload('vendor-due-diligence.pdf', 'application/pdf', pdf.body.data.id)
    const list = await call(request, 'GET', `/api/ChangeRequest/${crId}/Attachments`, { label: 'attachments' })
    const pdfs = list.body.data.filter((a: any) => a.fileName === 'vendor-due-diligence.pdf').map((a: any) => a.versionNumber).sort()
    actual(`pdf v${pdf.body.data.version}, docx v${docx.body.data.version}, xlsx v${xlsx.body.data.version}; replacement (supersedesAttachmentId) -> ${v2.status} "${v2.body?.message ?? 'v' + v2.body?.data?.version}"; pdf versions stored: [${pdfs}]`)
    defect('DEF-008')
    expect(v2.status, 'replacing a document must create version 2').toBe(200)
    expect(v2.body.data.version).toBe(2)
    expect(pdfs).toEqual([1, 2])
  })

  test('TC-API-018 Unsupported / unsafe file types are rejected with a clear message', async ({ request }) => {
    tc({ id: 'TC-API-018', story: 'US-1.2', type: 'Negative', priority: 'P1', steps: ['Upload unsupported.txt as text/plain', 'Upload malicious.exe as application/x-msdownload', 'Upload malicious.exe spoofed as application/pdf'], expected: 'All three rejected with 400 and a message naming the allowed formats' })
    defect('DEF-006')
    const po = await userId(request, USERS.po)
    const cr = await call(request, 'POST', '/api/ChangeRequest/Submit', { data: { changeType: 'Vendor', title: qaTitle('bad uploads'), description: 'x', submittedByUserId: po }, label: 'submit' })
    const up = (file: string, mime: string, label: string) =>
      call(request, 'POST', '/api/ChangeRequest/AttachDocumentFile', { multipart: { changeRequestId: cr.body.data.id, uploadedByUserId: po, file: { name: file, mimeType: mime, buffer: fs.readFileSync(path.join(FIXTURES, file)) } }, label })
    const txt = await up('unsupported.txt', 'text/plain', 'txt')
    const exe = await up('malicious.exe', 'application/x-msdownload', 'exe')
    const spoof = await up('malicious.exe', 'application/pdf', 'exe spoofed as pdf')
    actual(`txt -> ${txt.status} "${txt.body?.message}"; exe -> ${exe.status} "${exe.body?.message}"; exe-as-pdf -> ${spoof.status} "${spoof.body?.message ?? JSON.stringify(spoof.body?.data)}"`)
    expect.soft(txt.status).toBe(400)
    expect.soft(exe.status).toBe(400)
    expect.soft(spoof.status).toBe(400)
    expect.soft(`${txt.body?.message}`).toMatch(/PDF, DOCX, XLSX/)
  })

  test('TC-API-019 Clarification request is recorded against the change request', async ({ request }) => {
    tc({ id: 'TC-API-019', story: 'US-1.3', type: 'API', priority: 'P3', steps: ['POST /api/ChangeRequest/{id}/RequestClarification as analyst', 'GET audit trail'], expected: '200 with clarification id; audit trail shows who asked what' })
    const po = await userId(request, USERS.po)
    const an = await userId(request, USERS.analyst)
    const cr = await call(request, 'POST', '/api/ChangeRequest/Submit', { data: { changeType: 'Geography', title: qaTitle('clarification'), description: 'x', submittedByUserId: po }, label: 'submit' })
    const r = await call(request, 'POST', `/api/ChangeRequest/${cr.body.data.id}/RequestClarification`, { data: { requestedByUserId: an, question: 'Which target countries exactly?' } })
    expect(r.status).toBe(200)
    const trail = await call(request, 'GET', `/api/Audit/${cr.body.data.id}`, { label: 'audit' })
    const ev = trail.body.data.map((e: any) => `${e.entityType}.${e.action}`)
    actual(`clarification id ${r.body.data}; audit events: ${ev.join(', ')}`)
    expect(ev.join(',')).toMatch(/Clarification/i)
  })

  test('TC-API-020 External snapshot is ingested when a mock entity is linked', async ({ request }) => {
    tc({ id: 'TC-API-020', story: 'Data-Ingestion', type: 'API', priority: 'P2', steps: ['Submit a Product request linked to mock product "Cross-Border Wire Transfer Plus"', 'GET /api/DataIngestion/Snapshot/{id}', 'Submit a Process request (no linked entity)', 'GET snapshot'], expected: 'Linked request has a snapshot (200); unlinked request returns 404 "No external snapshot"' })
    const po = await userId(request, USERS.po)
    const linked = await call(request, 'POST', '/api/ChangeRequest/Submit', { data: { changeType: 'Product', title: qaTitle('snapshot linked'), description: 'x', submittedByUserId: po, mockProductId: 'b2222222-0000-0000-0000-000000000001' }, label: 'submit linked' })
    const plain = await call(request, 'POST', '/api/ChangeRequest/Submit', { data: { changeType: 'Process', title: qaTitle('snapshot none'), description: 'x', submittedByUserId: po }, label: 'submit plain' })
    const s1 = await call(request, 'GET', `/api/DataIngestion/Snapshot/${linked.body.data.id}`, { label: 'snapshot linked' })
    const s2 = await call(request, 'GET', `/api/DataIngestion/Snapshot/${plain.body.data.id}`, { label: 'snapshot none' })
    actual(`linked -> ${s1.status}; unlinked -> ${s2.status} "${s2.body?.message}"`)
    expect(s1.status).toBe(200)
    expect(s2.status).toBe(404)
  })
})
