// Summarise a Playwright JSON run: per-test status + per-defect status (from tc.defect annotations
// on each test, same rule as the report builder: defect reproduced if any linked test failed).
import fs from 'node:fs'
const file = process.argv[2]
const prevFile = process.argv[3]
const load = (f) => JSON.parse(fs.readFileSync(f, 'utf8'))
function collect(run) {
  const out = []
  const walk = (s) => {
    for (const c of s.suites || []) walk(c)
    for (const sp of s.specs || []) for (const t of sp.tests) {
      const r = t.results[t.results.length - 1] || {}
      const ann = [...(t.annotations || []), ...(r.annotations || [])]
      const id = ann.find((a) => a.type === 'tc.id')?.description || sp.title
      const defects = [...new Set(ann.filter((a) => a.type === 'tc.defect').map((a) => a.description))]
      const actual = ann.filter((a) => a.type === 'tc.actual').map((a) => a.description).join(' | ')
      const err = (r.error?.message || '').replace(/\u001b\[[0-9;]*m/g, '').split('\n').slice(0, 3).join(' ')
      out.push({ id, project: t.projectName, status: r.status || t.status, defects, actual, err, title: sp.title })
    }
  }
  for (const s of run.suites) walk(s)
  return out
}
const now = collect(load(file))
const prev = prevFile ? collect(load(prevFile)) : []
const prevById = Object.fromEntries(prev.map((t) => [t.id, t.status]))
const counts = {}
for (const t of now) counts[t.status] = (counts[t.status] || 0) + 1
console.log('COUNTS', JSON.stringify(counts), 'total', now.length)
console.log('\n== Tests whose status changed vs previous run')
for (const t of now) if (prevById[t.id] && prevById[t.id] !== t.status) console.log(t.id, prevById[t.id], '->', t.status, t.title)
console.log('\n== Non-passing tests')
for (const t of now) if (t.status !== 'passed') console.log(`${t.id} [${t.project}] ${t.status} defects=${t.defects.join(',')} :: ${t.actual.slice(0, 300)} :: ${t.err.slice(0, 250)}`)
const byDef = {}
for (const t of now) for (const d of t.defects) (byDef[d] ||= []).push(`${t.id}:${t.status}`)
console.log('\n== Defects -> linked tests on this run')
for (const d of Object.keys(byDef).sort()) {
  const any = byDef[d].some((x) => /failed|timedOut/.test(x))
  console.log(d, any ? 'REPRODUCED' : 'NOT REPRODUCED', byDef[d].join(' '))
}
