// File the re-verified defects as Azure Boards Bugs. Usage: node file-bugs.mjs <DEF-id,...|all> [--dry]
import { execFileSync } from 'node:child_process'
import fs from 'node:fs'
import { pathToFileURL } from 'node:url'

const E2E = 'C:/claude-personalLap/humaid-risk-governance/tests/e2e'
const { DEFECTS } = await import(pathToFileURL(`${E2E}/scripts/defects.mjs`).href)
const RUN = JSON.parse(fs.readFileSync(`${E2E}/results/reverify-0928.json`, 'utf8'))
const LOG = 'C:/Users/alaga/AppData/Local/Temp/claude/c--claude-personalLap-humaid-risk-governance/546d1b97-2a9b-4977-957a-af5e39ab6387/scratchpad/filed.json'
const filed = fs.existsSync(LOG) ? JSON.parse(fs.readFileSync(LOG, 'utf8')) : {}

// story work-item ids
const S = { '1.1': 2, '1.2': 3, '1.3': 4, '2.1': 6, '3.1': 9, '3.2': 10, '4.1': 12, '4.2': 13, '6.1': 18, '6.3': 20,
  '7.1': 22, '7.2': 23, '8.1': 25, '8.2': 26, '8.3': 27, '9.1': 29, '9.2': 30, '10.1': 32, '10.2': 33, '11.1': 37, '16.12': 75 }
const TAG = { '1.1': 'Intake', '1.2': 'Intake', '2.1': 'AI; Categorization', '3.1': 'AI; PolicyResearch', '3.2': 'PolicyResearch',
  '4.1': 'AI; Extraction', '4.2': 'Extraction', '6.1': 'Governance', '6.3': 'Governance', '7.1': 'Scoring', '7.2': 'Scoring',
  '8.2': 'Committee', '8.3': 'Committee', '9.1': 'AuditTrail', '10.1': 'Configuration', '11.1': 'Governance' }
const EPIC = { 1: 1, 2: 5, 3: 8, 4: 11, 6: 17, 7: 21, 8: 24, 9: 28, 10: 31, 11: 34, 13: 36 }

// id: [severity, priority, epic, [primary story, ...related], extra note]
const MAP = {
  'DEF-001': ['1 - Critical', 1, 6, ['6.3', '8.1']],
  'DEF-002': ['1 - Critical', 1, 11, ['11.1', '8.2', '6.3', '10.1']],
  'DEF-010': ['1 - Critical', 1, 11, ['11.1', '16.12'], 'The dev tfvars on main still set ASPNETCORE_ENVIRONMENT = "Development" (iac/environments/dev/parameters.ca.auto.tfvars).'],
  'DEF-007': ['2 - High', 1, 6, ['6.3']],
  'DEF-003': ['2 - High', 1, 8, ['8.2', '9.2']],
  'DEF-020': ['2 - High', 1, 4, ['4.1']],
  'DEF-033': ['2 - High', 1, 4, ['4.2']],
  'DEF-008': ['2 - High', 2, 1, ['1.2']],
  'DEF-030': ['2 - High', 2, 8, ['8.2']],
  'DEF-016': ['2 - High', 2, 10, ['10.1', '9.2']],
  'DEF-021': ['2 - High', 2, 8, ['8.2', '8.1']],
  'DEF-006': ['2 - High', 2, 1, ['1.2']],
  'DEF-005': ['3 - Medium', 2, 7, ['7.1', '1.1', '3.2', '10.1', '10.2'], 'Also seen in TC-API-071: inherent 0 or 6 and effectiveness 1.5 or -0.2 each return 500 "Failed to calculate risk score."'],
  'DEF-022': ['3 - Medium', 2, 8, ['8.3', '1.3']],
  'DEF-032': ['3 - Medium', 2, 3, ['3.1']],
  'DEF-012': ['3 - Medium', 2, 2, ['2.1']],
  'DEF-013': ['3 - Medium', 2, 7, ['7.1']],
  'DEF-009': ['3 - Medium', 3, 1, ['1.1']],
  'DEF-011': ['3 - Medium', 3, 3, ['3.2']],
  'DEF-024': ['3 - Medium', 3, 1, ['1.1']],
  'DEF-026': ['3 - Medium', 3, 3, ['3.1']],
  'DEF-027': ['3 - Medium', 3, 4, ['4.2', '6.1']],
  'DEF-017': ['3 - Medium', 3, 13, ['11.1'], 'No story owns HTTP hardening; filed under Epic 13 (Non-Functional Requirements).'],
  'DEF-014': ['4 - Low', 3, 7, ['7.2']],
  'DEF-018': ['4 - Low', 3, 13, ['6.1', '11.1'], 'No story owns error-message hygiene; filed under Epic 13 (Non-Functional Requirements).'],
  'DEF-023': ['4 - Low', 4, 1, ['1.1']],
  'DEF-028': ['4 - Low', 4, 9, ['9.1']],
}
// DEF-028 is narrowed: the PDF export (US-9.3) now includes before/after, but the on-screen Audit tab does not.
const OVERRIDE = {
  'DEF-032': {
    title: 'Policy corpus is too thin - a broad query returns only 5 passages; wire transfer and high-risk jurisdiction return nothing',
    actual: 'A broad query returns 5 passages in total. Topic searches: wire transfer = 0, high-risk jurisdiction = 0, correspondent banking = 3, PEP / sanctions / MSB / prepaid / cash-intensive = 1 each.',
  },
  'DEF-028': {
    title: 'Audit tab entries do not show the before/after state of what changed',
    expected: 'Each history entry viewed on screen shows actor, exact timestamp and the before/after state of whatever changed (US-9.1 AC2).',
    actual: 'The Audit tab lists entity.action, actor and reason only. The before/after values are stored and appear in the "Export PDF" document (US-9.3 is met), but not on screen.',
    rootCause: 'AuditTab in webapp/src/pages/AssessmentWorkspace.jsx renders only entityType, action, actor and reason.',
    fix: 'Render beforeValueJson / afterValueJson (summarised, expandable) on each audit entry, reusing the summary logic from AuditExportService.',
  },
}

// linked tests + this run's observed result
const tests = []
const walk = (s) => { for (const c of s.suites || []) walk(c); for (const sp of s.specs || []) for (const t of sp.tests) {
  const r = t.results.at(-1) || {}; const ann = [...(t.annotations || []), ...(r.annotations || [])]
  tests.push({ id: ann.find((a) => a.type === 'tc.id')?.description, title: sp.title, status: r.status,
    defects: ann.filter((a) => a.type === 'tc.defect').map((a) => a.description),
    steps: JSON.parse(ann.find((a) => a.type === 'tc.steps')?.description || '[]'),
    actual: [...new Set(ann.filter((a) => a.type === 'tc.actual').map((a) => a.description))].join(' ') }) } }
RUN.suites.forEach(walk)

const esc = (s) => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
const AZPY = 'C:/Program Files/Microsoft SDKs/Azure/CLI2/python.exe'
const az = (args) => execFileSync(AZPY, ['-IBm', 'azure.cli', ...args.map(String)], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] })
// shell:true on Windows -> quote each arg for cmd.exe
const q = (s) => String(s)

const want = process.argv[2] === 'all' ? Object.keys(MAP) : process.argv[2].split(',')
const dry = process.argv.includes('--dry')
for (const id of want) {
  if (filed[id]) { console.log(id, 'already filed as', filed[id]); continue }
  const d = { ...DEFECTS.find((x) => x.id === id), ...(OVERRIDE[id] || {}) }
  const [sev, pri, epic, stories, note] = MAP[id]
  const linked = id === 'DEF-028' ? [] : tests.filter((t) => t.defects.includes(id) || (id === 'DEF-005' && t.id === 'TC-API-071'))
  const primary = linked[0]
  const repro = [
    `<p><b>Environment:</b> deployed dev Workbench (https://ca-gh-hrg-workbench-dev.jollyplant-1cbb4459.eastus2.azurecontainerapps.io), release/1.00 @ 6112122. Re-verified 28 Sep 2026 by the Playwright e2e suite (tests/e2e); first reported 25 Sep 2026 as ${id} in docs/qa/test-execution-report.</p>`,
    primary?.steps?.length ? `<p><b>Steps to reproduce</b> (${esc(primary.title)}):</p><ol>${primary.steps.map((s) => `<li>${esc(s)}</li>`).join('')}</ol>` : '',
    `<p><b>Expected:</b> ${esc(d.expected)}</p>`,
    `<p><b>Actual:</b> ${esc(d.actual)}</p>`,
    linked.length ? `<p><b>Observed on 28 Sep re-run:</b></p><ul>${linked.map((t) => `<li>${esc(t.id)} (${esc(t.status)}): ${esc(t.actual)}</li>`).join('')}</ul>` : '',
    `<p><b>Probable root cause:</b> ${esc(d.rootCause)}</p>`,
    `<p><b>Suggested fix:</b> ${esc(d.fix)}</p>`,
    note ? `<p><b>Note:</b> ${esc(note)}</p>` : '',
    `<p><b>Requirement:</b> ${stories.map((s) => 'US-' + s).join(', ')}${d.stories ? ' (register: ' + esc(d.stories) + ')' : ''}</p>`,
  ].join('')
  const ac = `<ul><li>Given the steps above, when they are repeated on the deployed dev environment, then the expected behaviour occurs.</li>${linked.length ? `<li>Given the e2e suite, when ${linked.map((t) => t.id).join(', ')} run, then they pass.</li>` : ''}</ul>`
  const title = `${id} - ${d.title}`.slice(0, 255)
  if (dry) { console.log(title, '|', sev, 'P' + pri, '| Epic', epic, '| stories', stories.join(','), '| tests', linked.map((t) => t.id).join(',')); continue }
  const out = JSON.parse(az(['boards', 'work-item', 'create', '--type', 'Bug', '--title', q(title), '--output', 'json', '--fields',
    q(`Microsoft.VSTS.TCM.ReproSteps=${repro}`), q(`Microsoft.VSTS.Common.AcceptanceCriteria=${ac}`),
    q(`Microsoft.VSTS.Common.Severity=${sev}`), q(`Microsoft.VSTS.Common.Priority=${pri}`),
    q(`System.Tags=${epic === 13 ? 'Governance' : TAG[stories[0]]}`)]))
  const wid = out.id
  filed[id] = wid; fs.writeFileSync(LOG, JSON.stringify(filed, null, 2))
  az(['boards', 'work-item', 'relation', 'add', '--id', wid, '--relation-type', 'parent', '--target-id', EPIC[epic], '-o', 'none'])
  az(['boards', 'work-item', 'relation', 'add', '--id', wid, '--relation-type', 'related', '--target-id', stories.map((s) => S[s]).join(','), '-o', 'none'])
  console.log(id, '->', wid, sev, 'P' + pri)
}
