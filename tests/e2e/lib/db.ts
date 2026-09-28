import fs from 'node:fs'
import path from 'node:path'
import { Client } from 'pg'
import { evidence } from './harness'

// Read-only access to the Azure dev database for data testing. Three independent guards keep this
// suite incapable of writing, even if a query below were wrong:
//   1. the session is opened with default_transaction_read_only=on;
//   2. every query runs inside BEGIN READ ONLY ... ROLLBACK;
//   3. TC-DB-000 fails the run if the server does not report transaction_read_only=on.
// Credentials come from DB_URL or tests/e2e/.env.db (git-ignored) and are never logged.

export function dbUrl(): string | undefined {
  if (process.env.DB_URL) return process.env.DB_URL
  const f = path.join(__dirname, '..', '.env.db')
  if (!fs.existsSync(f)) return undefined
  const line = fs.readFileSync(f, 'utf8').split(/\r?\n/).find((l) => l.startsWith('DB_URL='))
  return line?.slice('DB_URL='.length).trim() || undefined
}

/** Server/database/user only - safe to print (no password). */
export function describeTarget(url: string) {
  const u = new URL(url)
  return `${u.username}@${u.hostname}:${u.port || 5432}/${u.pathname.slice(1)}`
}

export async function connect() {
  const url = dbUrl()!
  const client = new Client({
    connectionString: url,
    ssl: /localhost|127\.0\.0\.1/.test(url) ? undefined : { rejectUnauthorized: false },
    options: '-c default_transaction_read_only=on -c statement_timeout=30000',
    application_name: 'qa-readonly-data-tests',
  })
  await client.connect()
  return client
}

/** Runs one SELECT in a read-only transaction and captures query + rows as evidence. */
export async function q<T = any>(client: Client, label: string, sql: string, params: unknown[] = []): Promise<T[]> {
  await client.query('BEGIN READ ONLY')
  try {
    const t = Date.now()
    const res = await client.query(sql, params)
    await evidence(label, { sql: sql.replace(/\s+/g, ' ').trim(), params, durationMs: Date.now() - t, rowCount: res.rowCount, rows: res.rows.slice(0, 200) })
    return res.rows as T[]
  } finally {
    await client.query('ROLLBACK')
  }
}
