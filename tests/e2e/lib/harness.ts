import fs from 'node:fs'
import path from 'node:path'
import { test, type APIRequestContext, type APIResponse, type Page, type TestInfo } from '@playwright/test'

// Every test registers its test-case metadata here as Playwright annotations. The report builder
// (scripts/build-report.mjs) reads them back out of results.json, so the test-case catalogue and
// the execution report are generated from the same source - they can't drift apart.
export type TestCaseMeta = {
  id: string
  story: string // user story / requirement reference, e.g. "US-1.1" or "NFR-SEC"
  type: 'Functional' | 'API' | 'Data' | 'Negative' | 'Security' | 'Performance' | 'Accessibility' | 'Responsive' | 'E2E'
  priority: 'P1' | 'P2' | 'P3'
  steps: string[]
  expected: string
}

export function tc(meta: TestCaseMeta, info: TestInfo = test.info()) {
  info.annotations.push(
    { type: 'tc.id', description: meta.id },
    { type: 'tc.story', description: meta.story },
    { type: 'tc.type', description: meta.type },
    { type: 'tc.priority', description: meta.priority },
    { type: 'tc.steps', description: JSON.stringify(meta.steps) },
    { type: 'tc.expected', description: meta.expected },
  )
}

/** Records what was actually observed - shown next to "expected" in the report. */
export function actual(text: string, info: TestInfo = test.info()) {
  info.annotations.push({ type: 'tc.actual', description: text })
}

/** Links a failing expectation to a logged defect id (see DEFECTS in scripts/defects.mjs). */
export function defect(id: string, info: TestInfo = test.info()) {
  info.annotations.push({ type: 'tc.defect', description: id })
}

const EVIDENCE_DIR = path.join(__dirname, '..', 'evidence')

function tcIdOf(info: TestInfo) {
  return info.annotations.find((a) => a.type === 'tc.id')?.description || 'UNTAGGED'
}

function evidencePath(info: TestInfo, label: string, ext: string) {
  const dir = path.join(EVIDENCE_DIR, info.project.name)
  fs.mkdirSync(dir, { recursive: true })
  const n = info.attachments.filter((a) => a.name.startsWith('evidence:')).length + 1
  const safe = label.replace(/[^a-z0-9]+/gi, '-').replace(/^-|-$/g, '').toLowerCase()
  return path.join(dir, `${tcIdOf(info)}_${String(n).padStart(2, '0')}_${safe}.${ext}`)
}

/** Full-page screenshot saved under evidence/<project>/ and attached to the test result. */
export async function snap(page: Page, label: string, info: TestInfo = test.info()) {
  const file = evidencePath(info, label, 'png')
  await page.screenshot({ path: file, fullPage: true })
  await info.attach(`evidence:${label}`, { path: file, contentType: 'image/png' })
}

/** Saves a JSON evidence file (API request/response pairs, measurements). */
export async function evidence(label: string, data: unknown, info: TestInfo = test.info()) {
  const file = evidencePath(info, label, 'json')
  fs.writeFileSync(file, JSON.stringify(data, null, 2))
  await info.attach(`evidence:${label}`, { path: file, contentType: 'application/json' })
}

export type Envelope<T = any> = { isSuccessful: boolean; data: T; message: string | null; [k: string]: any }

/**
 * One API call, captured as evidence (method, url, body, status, duration, response). Returns the
 * parsed body alongside status so assertions can target either.
 */
export async function call<T = any>(
  request: APIRequestContext,
  method: 'GET' | 'POST' | 'PUT' | 'DELETE' | 'PATCH',
  url: string,
  opts: { data?: unknown; multipart?: Record<string, any>; headers?: Record<string, string>; label?: string } = {},
) {
  const started = Date.now()
  const res: APIResponse = await request.fetch(url, {
    method,
    data: opts.data,
    multipart: opts.multipart,
    headers: opts.headers,
    failOnStatusCode: false,
    timeout: 200_000,
  })
  const ms = Date.now() - started
  const text = await res.text()
  let body: any = text
  try {
    body = JSON.parse(text)
  } catch {
    /* non-JSON body, keep text */
  }
  const multipartSummary = opts.multipart
    ? Object.fromEntries(Object.entries(opts.multipart).map(([k, v]) => [k, typeof v === 'object' && v?.name ? `<file ${v.name}>` : v]))
    : undefined
  await evidence(opts.label || `${method} ${url}`, {
    request: { method, url, body: opts.data ?? multipartSummary ?? null },
    response: { status: res.status(), durationMs: ms, headers: res.headers(), body: typeof body === 'string' ? body.slice(0, 4000) : body },
  })
  return { status: res.status(), body: body as Envelope<T>, ms, headers: res.headers() }
}

/** Unique, clearly-labelled synthetic test data (shared dev DB - make our rows easy to spot). */
export const RUN_ID = process.env.RUN_ID || new Date().toISOString().replace(/[-:T]/g, '').slice(0, 12)
export const qaTitle = (s: string) => `[QA-E2E ${RUN_ID}] ${s}`

export const FIXTURES = path.join(__dirname, '..', 'fixtures')
