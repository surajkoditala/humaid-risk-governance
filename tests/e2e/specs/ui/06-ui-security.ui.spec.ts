import { expect, test } from '@playwright/test'
import { actual, qaTitle, snap, tc } from '../../lib/harness'
import { enterApp, nav, userId, USERS } from '../../lib/app'

test.describe('UI security', () => {
  test('TC-UI-070 Stored XSS payloads in a request title are rendered as text', async ({ page, request }) => {
    tc({ id: 'TC-UI-070', story: 'NFR-SEC', type: 'Security', priority: 'P1', steps: ['Submit (API) a request titled <img src=x onerror=window.__xss=1><script>window.__xss=2</script>', 'Open My Requests (PO) and Assessments (Analyst)', 'Check window.__xss and dialogs'], expected: 'Payload shown literally; no script executes' })
    const po = await userId(request, USERS.po)
    const payload = `<img src=x onerror="window.__xss=1"><script>window.__xss=2</script>`
    const r = await request.post('/api/ChangeRequest/Submit', { data: { changeType: 'Feature', title: qaTitle(payload), description: payload, submittedByUserId: po } })
    const crNumber = (await r.json()).data.requestNumber
    let dialog = false
    page.on('dialog', async (d) => {
      dialog = true
      await d.dismiss()
    })
    await enterApp(page, USERS.po)
    await nav(page, 'My Requests')
    const row = page.getByRole('row').filter({ hasText: crNumber })
    await expect(row).toContainText('<img src=x')
    await snap(page, 'payload in my requests')
    await enterApp(page, USERS.analyst)
    await nav(page, 'Assessments')
    await expect(page.getByRole('row').filter({ hasText: crNumber })).toContainText('<script>')
    await snap(page, 'payload in inbox')
    const xss = await page.evaluate(() => (window as any).__xss)
    actual(`${crNumber}: payload rendered as literal text; window.__xss=${xss}; dialog=${dialog}`)
    expect(xss).toBeUndefined()
    expect(dialog).toBe(false)
  })
})
