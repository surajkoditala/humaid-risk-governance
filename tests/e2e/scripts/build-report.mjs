// Builds the test-execution deliverable from a Playwright run:
//   docs/qa/test-execution-report/
//     index.html            - execution report (summary, defects, traceability, every test case + evidence)
//     test-execution-report.pdf
//     test-cases.csv        - test-case catalogue (id, story, type, priority, steps, expected)
//     test-results.csv      - execution results (status, actual, defects, duration)
//     defects.csv           - defect register
//     evidence/<project>/   - every screenshot + JSON request/response captured by the suite
//     playwright-report/    - Playwright's own HTML report (traces for failures)
// Usage: node scripts/build-report.mjs   (after `npx playwright test`)
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { chromium } from '@playwright/test'
import { DEFECTS } from './defects.mjs'

const ROOT = path.dirname(path.dirname(fileURLToPath(import.meta.url)))
const OUT = path.resolve(ROOT, '..', '..', 'docs', 'qa', 'test-execution-report')
const results = JSON.parse(fs.readFileSync(path.join(ROOT, 'results', 'results.json'), 'utf8'))
const read = (f, d = '') => (fs.existsSync(path.join(ROOT, 'results', f)) ? fs.readFileSync(path.join(ROOT, 'results', f), 'utf8').trim() : d)
const RUN = { id: read('run-id.txt', 'n/a'), start: read('run-start.txt'), end: read('run-end.txt') }
const BASE_URL = results.config.projects[0]?.use?.baseURL || ''

// ---------------------------------------------------------------- collect test results
const rows = []
const walk = (suite, file) => {
  for (const spec of suite.specs || []) {
    for (const t of spec.tests) {
      const r = t.results.at(-1) || {}
      const ann = [...(t.annotations || []), ...(r.annotations || [])]
      const one = (k) => ann.find((a) => a.type === k)?.description || ''
      const many = (k) => [...new Set(ann.filter((a) => a.type === k).map((a) => a.description))]
      const id = one('tc.id') || spec.title.split(' ')[0]
      rows.push({
        id,
        title: spec.title.replace(/^TC-[A-Z0-9]+-\d+\s*/, ''),
        project: t.projectName,
        file,
        story: one('tc.story'),
        type: one('tc.type'),
        priority: one('tc.priority'),
        steps: one('tc.steps') ? JSON.parse(one('tc.steps')) : [],
        expected: one('tc.expected'),
        actual: many('tc.actual').join(' '),
        defects: many('tc.defect'),
        status: r.status === 'timedOut' ? 'failed' : r.status || 'skipped',
        skipReason: ann.find((a) => a.type === 'skip')?.description || '',
        durationMs: r.duration || 0,
        errors: (r.errors || []).map((e) => (e.message || '').replace(/\x1b\[[0-9;]*m/g, '').split('\n').slice(0, 4).join(' ').trim()),
        autoShot: (r.attachments || []).find((a) => a.name === 'screenshot' && a.path)?.path,
      })
    }
  }
  for (const s of suite.suites || []) walk(s, file)
}
for (const s of results.suites) walk(s, s.file)
// Targeted re-executions after a test-script fix (results/rerun*.json) replace the original row.
const base = rows.splice(0)
const reruns = new Map()
for (const f of fs.readdirSync(path.join(ROOT, 'results')).filter((f) => /^rerun.*\.json$/.test(f)).sort()) {
  const before = rows.length
  for (const s of JSON.parse(fs.readFileSync(path.join(ROOT, 'results', f), 'utf8')).suites) walk(s, s.file)
  for (const r of rows.splice(before)) reruns.set(`${r.project}|${r.id}`, { ...r, rerun: true })
}
rows.push(...base.map((r) => reruns.get(`${r.project}|${r.id}`) || r))
rows.sort((a, b) => a.id.localeCompare(b.id, 'en', { numeric: true }))

// ---------------------------------------------------------------- evidence
fs.rmSync(OUT, { recursive: true, force: true })
fs.mkdirSync(OUT, { recursive: true })
fs.cpSync(path.join(ROOT, 'evidence'), path.join(OUT, 'evidence'), { recursive: true })
if (fs.existsSync(path.join(ROOT, 'playwright-report'))) fs.cpSync(path.join(ROOT, 'playwright-report'), path.join(OUT, 'playwright-report'), { recursive: true })
for (const r of rows) {
  const dir = path.join(OUT, 'evidence', r.project)
  fs.mkdirSync(dir, { recursive: true })
  if (r.autoShot && fs.existsSync(r.autoShot)) fs.copyFileSync(r.autoShot, path.join(dir, `${r.id}_99_final-state.png`))
  r.evidence = fs.readdirSync(dir).filter((f) => f.startsWith(`${r.id}_`)).sort().map((f) => `evidence/${r.project}/${f}`)
}

// ---------------------------------------------------------------- defects <-> tests
const byDefect = Object.fromEntries(DEFECTS.map((d) => [d.id, []]))
for (const r of rows) for (const d of r.defects) (byDefect[d] ||= []).push(r)
const defects = DEFECTS.map((d) => {
  const linked = byDefect[d.id] || []
  const failed = linked.filter((r) => r.status === 'failed')
  const status = !linked.length ? 'Observed (exploratory)' : failed.length ? 'Open - reproduced' : linked.every((r) => r.status === 'skipped') ? 'Not executed' : 'Not reproduced'
  return { ...d, linked, status }
})
const liveDefects = defects.filter((d) => d.status !== 'Not reproduced' && d.status !== 'Not executed')

// ---------------------------------------------------------------- metrics
const count = (xs, s) => xs.filter((r) => r.status === s).length
const total = rows.length
const passed = count(rows, 'passed')
const failed = count(rows, 'failed')
const skipped = count(rows, 'skipped')
const executed = passed + failed
const sev = ['Critical', 'High', 'Medium', 'Low'].map((s) => [s, liveDefects.filter((d) => d.severity === s).length])
const groupBy = (key) => {
  const m = new Map()
  for (const r of rows) {
    const k = r[key] || '(none)'
    if (!m.has(k)) m.set(k, { k, total: 0, passed: 0, failed: 0, skipped: 0 })
    const g = m.get(k)
    g.total++
    g[r.status]++
  }
  return [...m.values()]
}
const byType = groupBy('type').sort((a, b) => b.total - a.total)
const byProject = groupBy('project')
const stories = new Map()
for (const r of rows)
  for (const s of (r.story || '(none)').split('/').map((x) => x.trim()).filter(Boolean)) {
    if (!stories.has(s)) stories.set(s, [])
    stories.get(s).push(r)
  }
const storyRows = [...stories.entries()].sort((a, b) => a[0].localeCompare(b[0], 'en', { numeric: true }))

// ---------------------------------------------------------------- CSVs
const csv = (header, data) => [header, ...data].map((row) => row.map((v) => `"${String(v ?? '').replace(/"/g, '""')}"`).join(',')).join('\r\n')
fs.writeFileSync(path.join(OUT, 'test-cases.csv'), '﻿' + csv(['Test case ID', 'Title', 'Requirement', 'Type', 'Priority', 'Project', 'Steps', 'Expected result'], rows.map((r) => [r.id, r.title, r.story, r.type, r.priority, r.project, r.steps.map((s, i) => `${i + 1}. ${s}`).join('\n'), r.expected])))
fs.writeFileSync(path.join(OUT, 'test-results.csv'), '﻿' + csv(['Test case ID', 'Title', 'Project', 'Status', 'Duration (s)', 'Actual result', 'Defects', 'Failure detail', 'Evidence files'], rows.map((r) => [r.id, r.title, r.project, r.status.toUpperCase(), (r.durationMs / 1000).toFixed(1), r.actual || r.skipReason, r.defects.join(' '), r.errors.join(' | '), r.evidence.join('\n')])))
fs.writeFileSync(path.join(OUT, 'defects.csv'), '﻿' + csv(['Defect ID', 'Severity', 'Status', 'Area', 'Requirement', 'Title', 'Expected', 'Actual', 'Probable root cause', 'Suggested fix', 'Linked tests'], defects.map((d) => [d.id, d.severity, d.status, d.area, d.stories, d.title, d.expected, d.actual, d.rootCause, d.fix, d.linked.map((r) => `${r.id} (${r.status})`).join(' ')])))

// ---------------------------------------------------------------- HTML
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c])
const pill = (s) => `<span class="pill ${esc(s.toLowerCase().split(' ')[0])}">${esc(s)}</span>`
const pct = (n, d) => (d ? Math.round((n / d) * 100) : 0)
const bar = (g) => `<div class="bar" title="${g.passed} passed / ${g.failed} failed / ${g.skipped} skipped"><i class="p" style="width:${pct(g.passed, g.total)}%"></i><i class="f" style="width:${pct(g.failed, g.total)}%"></i><i class="s" style="width:${pct(g.skipped, g.total)}%"></i></div>`

const tcCard = (r) => {
  const imgs = r.evidence.filter((e) => e.endsWith('.png'))
  const json = r.evidence.filter((e) => e.endsWith('.json'))
  return `<article class="tc" id="${esc(r.id)}" data-status="${r.status}" data-text="${esc((r.id + ' ' + r.title + ' ' + r.story + ' ' + r.type + ' ' + r.defects.join(' ')).toLowerCase())}">
  <header><h4><span class="mono">${esc(r.id)}</span> ${esc(r.title)}</h4><span>${r.rerun ? '<span class="pill low" title="Re-executed individually after a test-script fix">re-run</span> ' : ''}${pill(r.status.toUpperCase())}</span></header>
  <dl class="meta"><div><dt>Requirement</dt><dd>${esc(r.story)}</dd></div><div><dt>Type</dt><dd>${esc(r.type)}</dd></div><div><dt>Priority</dt><dd>${esc(r.priority)}</dd></div><div><dt>Project</dt><dd>${esc(r.project)}</dd></div><div><dt>Duration</dt><dd>${(r.durationMs / 1000).toFixed(1)} s</dd></div>${r.defects.length ? `<div><dt>Defects</dt><dd>${r.defects.map((d) => `<a href="#${d}">${d}</a>`).join(' ')}</dd></div>` : ''}</dl>
  <div class="grid2"><div><h5>Steps</h5><ol>${r.steps.map((s) => `<li>${esc(s)}</li>`).join('')}</ol><h5>Expected</h5><p>${esc(r.expected)}</p></div>
  <div><h5>Actual</h5><p>${esc(r.actual || r.skipReason || '—')}</p>${r.errors.length ? `<h5>Failure detail</h5><pre>${esc(r.errors.join('\n').slice(0, 1200))}</pre>` : ''}</div></div>
  ${imgs.length || json.length ? `<h5>Evidence (${imgs.length} screenshot${imgs.length === 1 ? '' : 's'}, ${json.length} JSON)</h5><div class="shots">${imgs.map((e) => `<a href="${e}" target="_blank"><img loading="lazy" src="${e}" alt="${esc(path.basename(e))}"><span>${esc(path.basename(e, '.png').replace(/^[^_]+_\d+_/, ''))}</span></a>`).join('')}</div>${json.length ? `<ul class="json">${json.map((e) => `<li><a href="${e}" target="_blank">${esc(path.basename(e))}</a></li>`).join('')}</ul>` : ''}` : ''}
</article>`
}

const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Workbench Test Execution Report</title>
<style>
:root{--bg:#f6f7f9;--card:#fff;--ink:#16202b;--mut:#5b6775;--line:#e2e6eb;--ok:#1a7f4b;--okb:#e5f5ec;--bad:#b42318;--badb:#fdecea;--warn:#9a6700;--warnb:#fff4d6;--sk:#6b7280;--skb:#eef0f3;--acc:#0b5cad}
@media (prefers-color-scheme:dark){:root{--bg:#0f141a;--card:#161d25;--ink:#e6edf3;--mut:#9aa7b4;--line:#27313c;--okb:#12301f;--badb:#3a1512;--warnb:#3a2d0c;--skb:#222a33;--ok:#5bd394;--bad:#ff7b72;--warn:#e3b341;--acc:#6cb6ff}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:14px/1.5 system-ui,-apple-system,Segoe UI,Roboto,sans-serif}
main{max-width:1200px;margin:0 auto;padding:24px 16px 64px}h1{font-size:26px;margin:0 0 4px}h2{font-size:19px;margin:36px 0 12px;padding-bottom:6px;border-bottom:1px solid var(--line)}h4{margin:0;font-size:15px}h5{margin:12px 0 4px;font-size:12px;text-transform:uppercase;letter-spacing:.04em;color:var(--mut)}
a{color:var(--acc)}.mono{font-family:ui-monospace,Consolas,monospace}.mut{color:var(--mut)}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:16px}
.kpis{display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));gap:12px;margin:16px 0}.kpi{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:12px 14px}.kpi b{display:block;font-size:26px}.kpi span{color:var(--mut);font-size:12px}
table{width:100%;border-collapse:collapse;background:var(--card);border:1px solid var(--line);border-radius:10px;overflow:hidden}th,td{text-align:left;padding:8px 10px;border-bottom:1px solid var(--line);vertical-align:top}th{font-size:12px;color:var(--mut);background:var(--bg)}
.tw{overflow-x:auto}.pill{display:inline-block;padding:1px 8px;border-radius:99px;font-size:12px;font-weight:600;white-space:nowrap}
.passed,.not{background:var(--okb);color:var(--ok)}.failed,.critical,.open{background:var(--badb);color:var(--bad)}.high{background:var(--badb);color:var(--bad);opacity:.85}.medium,.observed{background:var(--warnb);color:var(--warn)}.low,.skipped{background:var(--skb);color:var(--sk)}
.bar{display:flex;height:8px;border-radius:4px;overflow:hidden;background:var(--skb);min-width:120px}.bar i{display:block}.bar .p{background:var(--ok)}.bar .f{background:var(--bad)}.bar .s{background:var(--sk)}
.tc{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:14px 16px;margin:12px 0}.tc header{display:flex;justify-content:space-between;gap:12px;align-items:flex-start}
.meta{display:flex;flex-wrap:wrap;gap:6px 22px;margin:8px 0 0}.meta div{display:flex;gap:6px}.meta dt{color:var(--mut)}.meta dd{margin:0}
.grid2{display:grid;grid-template-columns:1fr 1fr;gap:18px}@media(max-width:760px){.grid2{grid-template-columns:1fr}}
ol{margin:0;padding-left:20px}pre{white-space:pre-wrap;word-break:break-word;background:var(--bg);border:1px solid var(--line);border-radius:6px;padding:8px;font-size:12px;margin:0}
.shots{display:grid;grid-template-columns:repeat(auto-fill,minmax(170px,1fr));gap:10px}.shots a{text-decoration:none;color:var(--mut);font-size:11px}.shots img{width:100%;height:110px;object-fit:cover;object-position:top;border:1px solid var(--line);border-radius:6px;display:block}
.json{columns:2;font-size:12px;margin:6px 0 0;padding-left:18px}@media(max-width:760px){.json{columns:1}}
.filters{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin:8px 0}.filters button{border:1px solid var(--line);background:var(--card);color:var(--ink);border-radius:99px;padding:4px 12px;cursor:pointer}.filters button.on{background:var(--acc);color:#fff;border-color:var(--acc)}.filters input{flex:1;min-width:200px;padding:6px 10px;border:1px solid var(--line);border-radius:8px;background:var(--card);color:var(--ink)}
details.def{background:var(--card);border:1px solid var(--line);border-radius:10px;margin:8px 0;padding:10px 14px}details.def summary{cursor:pointer;display:flex;gap:10px;align-items:baseline;flex-wrap:wrap}details.def dl{display:grid;grid-template-columns:150px 1fr;gap:4px 12px;margin:10px 0 0}details.def dt{color:var(--mut)}details.def dd{margin:0}@media(max-width:760px){details.def dl{grid-template-columns:1fr}}
@media print{.filters,.shots,.json{display:none}.tc,details.def{break-inside:avoid}details.def{display:block}body{background:#fff}}
</style></head><body><main>
<h1>Risk Assessment Workbench — Test Execution Report</h1>
<p class="mut">HumAId Risk Governance · Genius Hacks Q3 2026 · QA · Run <span class="mono">${esc(RUN.id)}</span> · ${esc(RUN.start)} → ${esc(RUN.end)} (UTC)</p>

<div class="kpis">
<div class="kpi"><b>${total}</b><span>test cases executed</span></div>
<div class="kpi"><b style="color:var(--ok)">${passed}</b><span>passed</span></div>
<div class="kpi"><b style="color:var(--bad)">${failed}</b><span>failed</span></div>
<div class="kpi"><b>${skipped}</b><span>skipped / blocked</span></div>
<div class="kpi"><b>${pct(passed, executed)}%</b><span>pass rate (executed)</span></div>
<div class="kpi"><b style="color:var(--bad)">${liveDefects.length}</b><span>open defects · ${sev.map(([s, n]) => `${n} ${s}`).join(' · ')}</span></div>
</div>

<h2>1. Summary</h2>
<div class="card">
<p><b>Verdict: not ready for release.</b> The core workflow works end to end — a request can be submitted, assessed with AI assistance, finalized, voted on and decided, with an append-only audit trail that exports to PDF — and several governance rules hold: residual risk can never reach zero, a mitigation cap of 1.0 or more is rejected, override and edit reasons are mandatory, AI drafts block finalization, and audit records cannot be edited or deleted.</p>
<p>However, ${sev[0][1]} critical defects defeat the human-in-the-loop controls the product exists to enforce:</p>
<ul>
<li>the finalize gate passes on an empty assessment;</li>
<li>any user id can be submitted as the acting finalizer, voter or config author;</li>
<li>the public deployment runs in Development mode with authentication bypassed.</li>
</ul>
<p>High-severity gaps include:</p>
<ul>
<li>finalized assessments are not locked;</li>
<li>committee votes can be silently overwritten;</li>
<li>document versioning fails;</li>
<li>UI document extraction never reads the document, and correcting an extracted field from the UI always fails;</li>
<li>committee members vote without seeing the assessment.</li>
</ul>
</div>

<h2>2. Scope, approach and environment</h2>
<div class="card grid2">
<div><h5>Application under test</h5><p><a href="${esc(BASE_URL)}">${esc(BASE_URL)}</a><br>Azure Container Apps (dev) · .NET 10 API + React SPA served from the same origin · PostgreSQL · Azure AI Foundry for the AI touchpoints · Blob storage for documents. Deployed bundle <span class="mono">index-YRyGki1L.js</span> (last modified 24 Sep 2026 17:45 UTC). It is newer than the <span class="mono">release/1.00</span> checkout used for code review (for example, it includes an audit PDF export), so treat the root-cause notes as pointers to verify against the deployed commit.</p>
<h5>Tooling</h5><p>Playwright ${esc(results.config.version)} (Chromium desktop 1440×900 and Pixel 7 emulation), @axe-core/playwright for WCAG 2.1 A/AA, Playwright API request context for REST testing. Every test records its own test-case ID, requirement, steps, expected and actual result, so this report and the CSV catalogue come from the executed code.</p>
<h5>Test data</h5><p>Synthetic only. Every record created is prefixed <span class="mono">[QA-E2E ${esc(RUN.id)}]</span>. Seeded users: Priya Owens (Product Owner), Amara Chen / Sam Okafor (Analysts), Jordan Blake / Riley Voss (Committee), Taylor Finch (Admin). Configuration values changed during testing were written back to their baseline values (mitigation cap 0.85, quorum 2).</p></div>
<div><h5>Test types</h5><table><tr><th>Type</th><th>Cases</th><th>Pass / Fail / Skip</th><th></th></tr>${byType.map((g) => `<tr><td>${esc(g.k)}</td><td>${g.total}</td><td>${g.passed} / ${g.failed} / ${g.skipped}</td><td>${bar(g)}</td></tr>`).join('')}</table>
<h5>Projects</h5><table><tr><th>Project</th><th>Cases</th><th>Pass / Fail / Skip</th><th></th></tr>${byProject.map((g) => `<tr><td>${esc(g.k)}</td><td>${g.total}</td><td>${g.passed} / ${g.failed} / ${g.skipped}</td><td>${bar(g)}</td></tr>`).join('')}</table>
<h5>Not covered in this run</h5><ul><li>Auth0 Universal Login flow, because no tenant is configured (see DEF-010).</li><li>E-mail and in-app notifications (US-1.3 AC2, US-8.1 AC2, US-8.3 AC2), which are not implemented.</li><li>Direct database immutability (US-9.2) at the SQL level; tested through the API only.</li><li>AI output quality at scale, which is covered by the /evals framework rather than this suite. Here AI outputs were checked for structure and grounding.</li><li>Load and soak testing beyond a 25-request burst.</li></ul></div>
</div>

<h2>3. Defect register (${defects.length})</h2>
<p class="mut">Status comes from this run: <b>Open - reproduced</b> means a linked test failed; <b>Not reproduced</b> means all linked tests passed.</p>
${defects.map((d) => `<details class="def" id="${d.id}"><summary><span class="mono">${d.id}</span>${pill(d.severity)}${pill(d.status)}<b>${esc(d.title)}</b></summary><dl>
<dt>Area</dt><dd>${esc(d.area)}</dd><dt>Requirement</dt><dd>${esc(d.stories)}</dd><dt>Expected</dt><dd>${esc(d.expected)}</dd><dt>Actual</dt><dd>${esc(d.actual)}</dd><dt>Probable root cause</dt><dd>${esc(d.rootCause)}</dd><dt>Suggested fix</dt><dd>${esc(d.fix)}</dd>
<dt>Linked tests</dt><dd>${d.linked.length ? d.linked.map((r) => `<a href="#${r.id}">${r.id}</a> ${pill(r.status.toUpperCase())}`).join(' &nbsp; ') : 'Exploratory observation - see TC-UI-003 / TC-UI-023 screenshots'}</dd></dl></details>`).join('')}

<h2>4. Requirements traceability</h2>
<div class="tw"><table><tr><th>Requirement</th><th>Test cases</th><th>Result</th><th></th></tr>
${storyRows.map(([s, rs]) => { const g = { total: rs.length, passed: count(rs, 'passed'), failed: count(rs, 'failed'), skipped: count(rs, 'skipped') }; return `<tr><td class="mono">${esc(s)}</td><td>${rs.map((r) => `<a href="#${r.id}">${r.id}</a>`).join(', ')}</td><td>${g.passed}/${g.total} passed</td><td>${bar(g)}</td></tr>` }).join('')}
</table></div>

<h2>5. Test cases and evidence (${total})</h2>
<div class="filters"><button data-f="all" class="on">All ${total}</button><button data-f="failed">Failed ${failed}</button><button data-f="passed">Passed ${passed}</button><button data-f="skipped">Skipped ${skipped}</button><input type="search" placeholder="Filter by id, story, type, defect…" id="q"></div>
<div id="tcs">${rows.map(tcCard).join('\n')}</div>

<h2>6. Deliverables in this folder</h2>
<div class="card"><ul>
<li><a href="test-cases.csv">test-cases.csv</a>: test-case catalogue (ID, requirement, type, priority, steps, expected).</li>
<li><a href="test-results.csv">test-results.csv</a>: execution result per case (status, actual, defects, evidence files).</li>
<li><a href="defects.csv">defects.csv</a>: defect register.</li>
<li><a href="evidence/">evidence/</a>: every screenshot (PNG) and API request/response capture (JSON), named <span class="mono">&lt;TC-ID&gt;_&lt;step&gt;_&lt;label&gt;</span>.</li>
<li><a href="playwright-report/index.html">playwright-report/</a>: Playwright's interactive report, with traces and videos for failed tests.</li>
<li>Source: <span class="mono">tests/e2e/</span>. Re-run with <span class="mono">npx playwright test &amp;&amp; npm run report</span>.</li>
</ul></div>
</main>
<script>
const btns=[...document.querySelectorAll('.filters button')],q=document.getElementById('q');let f='all';
function apply(){const t=q.value.trim().toLowerCase();document.querySelectorAll('.tc').forEach(e=>{e.style.display=(f==='all'||e.dataset.status===f)&&(!t||e.dataset.text.includes(t))?'':'none'})}
btns.forEach(b=>b.onclick=()=>{btns.forEach(x=>x.classList.remove('on'));b.classList.add('on');f=b.dataset.f;apply()});q.oninput=apply;
</script></body></html>`
fs.writeFileSync(path.join(OUT, 'index.html'), html)

// ---------------------------------------------------------------- PDF (print stylesheet drops the image gallery)
const browser = await chromium.launch()
const page = await browser.newPage()
await page.goto('file:///' + path.join(OUT, 'index.html').replace(/\\/g, '/'))
await page.evaluate(() => document.querySelectorAll('details').forEach((d) => d.setAttribute('open', '')))
await page.emulateMedia({ media: 'print', colorScheme: 'light' })
await page.pdf({ path: path.join(OUT, 'test-execution-report.pdf'), format: 'A4', margin: { top: '14mm', bottom: '14mm', left: '10mm', right: '10mm' }, printBackground: true })
await browser.close()

console.log(`Report: ${OUT}\\index.html  (${total} tests: ${passed} passed, ${failed} failed, ${skipped} skipped; ${liveDefects.length} open defects)`)
