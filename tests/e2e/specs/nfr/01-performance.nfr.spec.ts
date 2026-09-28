import { expect, test } from '@playwright/test'
import { actual, defect, evidence, snap, tc } from '../../lib/harness'
import { enterApp, nav, USERS } from '../../lib/app'

const pct = (xs: number[], p: number) => {
  const s = [...xs].sort((a, b) => a - b)
  return s[Math.min(s.length - 1, Math.ceil((p / 100) * s.length) - 1)]
}

test.describe('Performance', () => {
  test('TC-PERF-001 Read API latency (10 samples per endpoint)', async ({ request }) => {
    const endpoints = ['/api/Ping', '/api/User', '/api/ChangeRequest', '/api/Committee/Queue', '/api/CategoryMapping/Categories', '/api/PolicyResearch/Search?queryText=customer&topK=5']
    tc({ id: 'TC-PERF-001', story: 'NFR-PERF', type: 'Performance', priority: 'P2', steps: endpoints.map((e) => `GET ${e} x10`), expected: 'p95 < 1,500 ms for every read endpoint; no errors' })
    const rows: any[] = []
    for (const e of endpoints) {
      const ms: number[] = []
      for (let i = 0; i < 10; i++) {
        const t = Date.now()
        const r = await request.get(e)
        ms.push(Date.now() - t)
        expect(r.status()).toBe(200)
      }
      rows.push({ endpoint: e, p50: pct(ms, 50), p95: pct(ms, 95), max: Math.max(...ms), samples: ms })
    }
    await evidence('latency table', rows)
    actual(rows.map((r) => `${r.endpoint.replace('/api/', '')}: p50 ${r.p50} / p95 ${r.p95} ms`).join('; '))
    if (rows.some((r) => r.p95 >= 1500)) defect('DEF-031')
    for (const r of rows) expect.soft(r.p95, r.endpoint).toBeLessThan(1500)
  })

  test('TC-PERF-002 Burst of 25 concurrent reads', async ({ request }) => {
    tc({ id: 'TC-PERF-002', story: 'NFR-PERF', type: 'Performance', priority: 'P3', steps: ['Fire 25 parallel GET /api/ChangeRequest'], expected: 'All 200; p95 < 3,000 ms (Burstable-tier DB, 1 container)' })
    const t0 = Date.now()
    const results = await Promise.all(
      Array.from({ length: 25 }, async () => {
        const t = Date.now()
        const r = await request.get('/api/ChangeRequest')
        return { status: r.status(), ms: Date.now() - t }
      }),
    )
    const ms = results.map((r) => r.ms)
    const errors = results.filter((r) => r.status !== 200).length
    await evidence('burst results', { wallMs: Date.now() - t0, p50: pct(ms, 50), p95: pct(ms, 95), max: Math.max(...ms), errors, results })
    actual(`25 parallel: ${errors} errors; p50 ${pct(ms, 50)} ms, p95 ${pct(ms, 95)} ms, max ${Math.max(...ms)} ms; wall ${Date.now() - t0} ms`)
    expect(errors).toBe(0)
    expect.soft(pct(ms, 95)).toBeLessThan(3000)
  })

  test('TC-PERF-003 Initial page load and bundle size', async ({ page }) => {
    tc({ id: 'TC-PERF-003', story: 'NFR-PERF', type: 'Performance', priority: 'P2', steps: ['Cold load / in a fresh context', 'Read Navigation Timing and resource sizes'], expected: 'DOMContentLoaded < 2 s, load < 3 s; JS transferred < 500 KB' })
    await page.goto('/')
    await page.getByRole('button', { name: /Continue without signing in/ }).waitFor()
    const m = await page.evaluate(() => {
      const n = performance.getEntriesByType('navigation')[0] as PerformanceNavigationTiming
      const res = performance.getEntriesByType('resource') as PerformanceResourceTiming[]
      const js = res.filter((r) => r.name.endsWith('.js')).reduce((a, r) => a + (r.transferSize || r.encodedBodySize), 0)
      const css = res.filter((r) => r.name.endsWith('.css')).reduce((a, r) => a + (r.transferSize || r.encodedBodySize), 0)
      return { ttfb: Math.round(n.responseStart), dcl: Math.round(n.domContentLoadedEventEnd), load: Math.round(n.loadEventEnd), jsKB: Math.round(js / 1024), cssKB: Math.round(css / 1024) }
    })
    await evidence('navigation timing', m)
    await snap(page, 'loaded')
    actual(`TTFB ${m.ttfb} ms, DOMContentLoaded ${m.dcl} ms, load ${m.load} ms, JS ${m.jsKB} KB, CSS ${m.cssKB} KB`)
    if (m.dcl >= 2000 || m.load >= 3000 || m.jsKB >= 500) defect('DEF-031')
    expect.soft(m.dcl).toBeLessThan(2000)
    expect.soft(m.load).toBeLessThan(3000)
    expect.soft(m.jsKB).toBeLessThan(500)
  })

  test('TC-PERF-004 Screen-to-screen navigation responsiveness', async ({ page }) => {
    tc({ id: 'TC-PERF-004', story: 'NFR-PERF', type: 'Performance', priority: 'P3', steps: ['As Amara Chen click Assessments until the table renders', 'Open the first request until tabs render'], expected: 'Each transition renders in < 2 s' })
    await enterApp(page, USERS.analyst)
    let t = Date.now()
    await nav(page, 'Assessments')
    await page.getByRole('row').nth(1).waitFor()
    const inbox = Date.now() - t
    t = Date.now()
    await page.getByRole('button', { name: 'Open' }).first().click()
    await page.getByRole('tab', { name: 'Categories' }).waitFor()
    const ws = Date.now() - t
    await snap(page, 'workspace rendered')
    actual(`inbox table ${inbox} ms; workspace ${ws} ms`)
    expect.soft(inbox).toBeLessThan(2000)
    expect.soft(ws).toBeLessThan(2000)
  })
})
