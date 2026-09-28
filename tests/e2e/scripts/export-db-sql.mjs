// Exports the exact SQL the db suite executed (captured in evidence/db/*.json) as one script for
// manual validation in psql: docs/qa/db-validation/db-manual-validation.sql
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = path.dirname(path.dirname(fileURLToPath(import.meta.url)))
const EV = path.join(ROOT, 'evidence', 'db')
const OUT = path.resolve(ROOT, '..', '..', 'docs', 'qa', 'db-validation', 'db-manual-validation.sql')
const files = fs.readdirSync(EV).filter((f) => f.endsWith('.json')).sort((a, b) => a.localeCompare(b, 'en', { numeric: true }))

let out = `-- Manual read-only data validation - Risk Assessment Workbench
-- Same SQL the Playwright db suite ran (tests/e2e/specs/db/01-data-integrity.db.spec.ts).
-- Run:  docker exec -it risk-governance-postgres psql -U postgres -d risk_governance_db
-- then paste one block at a time, or run the whole file with \\i (see docs/qa/db-validation/README.md).

SET default_transaction_read_only = on;   -- safety: any write in this session now fails
SHOW transaction_read_only;               -- must print: on
\\x auto
`
let last = ''
for (const f of files) {
  const j = JSON.parse(fs.readFileSync(path.join(EV, f), 'utf8'))
  const tc = f.split('_')[0]
  const label = f.replace(/^[^_]+_\d+_/, '').replace('.json', '').replace(/-/g, ' ')
  if (tc !== last) {
    out += `\n-- =====================================================================\n-- ${tc}\n-- =====================================================================\n`
    last = tc
  }
  const sql = j.sql.replace(/\s+(FROM|WHERE|UNION ALL|LEFT JOIN|JOIN|GROUP BY|ORDER BY|HAVING)\s/g, '\n  $1 ').replace(/,\s+count\(\*\) FILTER/g, ',\n  count(*) FILTER')
  out += `\n\\echo '${tc}: ${label}'\n-- local Docker result: ${j.rowCount} row(s)\n${sql};\n`
}
fs.mkdirSync(path.dirname(OUT), { recursive: true })
fs.writeFileSync(OUT, out)
console.log(`${files.length} queries -> ${OUT}`)
