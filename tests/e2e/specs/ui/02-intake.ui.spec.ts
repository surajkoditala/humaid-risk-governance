import path from 'node:path'
import { expect, test } from '@playwright/test'
import { actual, defect, FIXTURES, qaTitle, snap, tc } from '../../lib/harness'
import { card, choose, enterApp, nav, toast, USERS } from '../../lib/app'
import { state } from '../../lib/state'

const K = (k: string) => `ui.${k}`

test.describe('Epic 1 - Intake (Product Owner UI)', () => {
  test.beforeEach(async ({ page }) => {
    await enterApp(page, USERS.po)
    await nav(page, 'Submit Request')
    await expect(card(page, 'Submit a change request')).toBeVisible()
  })

  test('TC-UI-020 Change type offers exactly the six defined types', async ({ page }) => {
    tc({ id: 'TC-UI-020', story: 'US-1.1', type: 'Functional', priority: 'P1', steps: ['Open Submit Request', 'Open the Change type dropdown'], expected: 'Product, Feature, Process, Vendor, Geography, CustomerSegment' })
    await card(page, 'Submit a change request').getByRole('combobox').first().click()
    const opts = await page.getByRole('option').allTextContents()
    await snap(page, 'change type options')
    await page.keyboard.press('Escape')
    actual(opts.join(', '))
    expect(opts).toEqual(['Product', 'Feature', 'Process', 'Vendor', 'Geography', 'CustomerSegment'])
  })

  test('TC-UI-021 Submitting with mandatory fields empty is blocked with a message', async ({ page }) => {
    tc({ id: 'TC-UI-021', story: 'US-1.1', type: 'Negative', priority: 'P1', steps: ['Leave all fields empty', 'Click Submit request', 'Fill only title', 'Click Submit request'], expected: 'Submission blocked; message lists the missing fields' })
    await page.getByRole('button', { name: 'Submit request', exact: true }).click()
    const t = toast(page, /required/)
    await expect(t).toBeVisible()
    await snap(page, 'empty form blocked')
    await page.getByLabel('Title').fill('only a title')
    await page.getByRole('button', { name: 'Submit request', exact: true }).click()
    await expect(toast(page, /required/)).toBeVisible()
    await snap(page, 'partial form blocked')
    const msg = await t.textContent()
    actual(`blocked with toast "${msg}" (generic - does not list which fields are missing; no inline field errors)`)
    defect('DEF-023')
    expect.soft(msg, 'message should name only the missing fields (change type, description)').not.toMatch(/title/i)
  })

  test('TC-UI-022 Type-specific fields appear for each change type', async ({ page }) => {
    tc({ id: 'TC-UI-022', story: 'US-1.1', type: 'Functional', priority: 'P1', steps: ['Select Vendor', 'Look for vendor name / jurisdiction / data access scope fields', 'Select Geography', 'Look for target country/region field', 'Select Process'], expected: 'Vendor shows vendor name, jurisdiction and data-access-scope fields; Geography shows target country/region; linked-entity lookup appears for Product/Feature/Vendor/Geography/CustomerSegment, not Process' })
    const form = card(page, 'Submit a change request')
    const trigger = form.getByRole('combobox').first()
    await choose(page, trigger, 'Vendor')
    await expect(form.getByText(/Linked vendor/)).toBeVisible()
    await snap(page, 'vendor selected')
    const vendorSpecific = await form.getByLabel(/jurisdiction/i).count()
    await choose(page, trigger, 'Geography')
    await snap(page, 'geography selected')
    const geoSpecific = await form.getByLabel(/country|region/i).count()
    await choose(page, trigger, 'Process')
    const processLinked = await form.getByText(/Linked /).count()
    await snap(page, 'process selected')
    actual(`Vendor: ${vendorSpecific} jurisdiction field(s); Geography: ${geoSpecific} country/region field(s); only a generic free-text "Type-specific details" box plus a linked-entity lookup; Process linked lookup shown: ${processLinked > 0}`)
    expect(processLinked).toBe(0)
    defect('DEF-024')
    expect.soft(vendorSpecific, 'Vendor requires structured vendor name / jurisdiction / data scope fields').toBeGreaterThan(0)
    expect.soft(geoSpecific, 'Geography requires a target country/region field').toBeGreaterThan(0)
  })

  test('TC-UI-023 Submit a Vendor change request end to end', async ({ page }) => {
    tc({ id: 'TC-UI-023', story: 'US-1.1', type: 'E2E', priority: 'P1', steps: ['Select Vendor', 'Enter title, description, details', 'Pick a linked vendor from the bank systems', 'Submit'], expected: 'Success toast with new CR number; form resets' })
    const form = card(page, 'Submit a change request')
    const title = qaTitle('UI lifecycle - onboard Malta settlement vendor')
    await choose(page, form.getByRole('combobox').first(), 'Vendor')
    await page.getByLabel('Title').fill(title)
    await page.getByLabel('Description').fill('Onboard QuickPay Processing Ltd (Malta) as card settlement processor; it will receive cardholder PII and settlement files over an API.')
    await page.getByLabel('Type-specific details').fill('Vendor: QuickPay Processing Ltd; jurisdiction: Malta; data access scope: cardholder PII')
    await choose(page, form.getByRole('combobox').nth(1), /.+/)
    await snap(page, 'form filled')
    await page.getByRole('button', { name: 'Submit request', exact: true }).click()
    const t = toast(page, /Submitted as CR-\d{4}-\d{5}/)
    await expect(t).toBeVisible()
    const crNumber = (await t.textContent())!.match(/CR-\d{4}-\d{5}/)![0]
    await snap(page, 'submitted toast')
    state.set(K('crNumber'), crNumber)
    state.set(K('title'), title)
    await expect(page.getByLabel('Title')).toHaveValue('')
    actual(`created ${crNumber}; form reset`)
  })

  test('TC-UI-024 Attach PDF, DOCX and XLSX to the request', async ({ page }) => {
    tc({ id: 'TC-UI-024', story: 'US-1.2', type: 'Functional', priority: 'P1', steps: ['In "Attach a supporting document" pick the new request', 'Choose vendor-due-diligence.pdf, Attach', 'Repeat with product-spec.docx and control-matrix.xlsx'], expected: 'Each upload shows "Document attached - text extracted server-side"' })
    const crNumber = state.need(K('crNumber'))
    const attach = card(page, 'Attach a supporting document')
    const results: string[] = []
    for (const f of ['vendor-due-diligence.pdf', 'product-spec.docx', 'control-matrix.xlsx']) {
      await choose(page, attach.getByRole('combobox'), new RegExp(crNumber))
      await page.locator('#file').setInputFiles(path.join(FIXTURES, f))
      await attach.getByRole('button', { name: 'Attach document' }).click()
      const t = toast(page, /Document attached/)
      await expect(t).toBeVisible({ timeout: 60_000 })
      await snap(page, `attached ${f}`)
      results.push(`${f}: attached`)
      await t.waitFor({ state: 'hidden', timeout: 10_000 }).catch(() => {})
    }
    actual(results.join('; '))
  })

  test('TC-UI-025 Unsupported file type is rejected with a clear message', async ({ page }) => {
    tc({ id: 'TC-UI-025', story: 'US-1.2', type: 'Negative', priority: 'P1', steps: ['Pick the request', 'Force-select unsupported.txt (bypassing the picker filter)', 'Attach'], expected: 'Error message naming the allowed formats (PDF, DOCX, XLSX)' })
    defect('DEF-006')
    const crNumber = state.need(K('crNumber'))
    const attach = card(page, 'Attach a supporting document')
    await choose(page, attach.getByRole('combobox'), new RegExp(crNumber))
    await page.locator('#file').setInputFiles(path.join(FIXTURES, 'unsupported.txt'))
    await attach.getByRole('button', { name: 'Attach document' }).click()
    const t = page.locator('[data-sonner-toast]').last()
    await expect(t).toBeVisible({ timeout: 30_000 })
    const msg = (await t.textContent()) || ''
    await snap(page, 'unsupported file result')
    actual(`toast: "${msg}"`)
    expect(msg).not.toMatch(/Document attached/)
    expect.soft(msg, 'message should state the allowed formats').toMatch(/PDF, DOCX, XLSX/)
  })

  test('TC-UI-026 Attach without choosing a file is blocked', async ({ page }) => {
    tc({ id: 'TC-UI-026', story: 'US-1.2', type: 'Negative', priority: 'P3', steps: ['Click Attach document with nothing selected'], expected: 'Toast "Pick a request and a file."' })
    await card(page, 'Attach a supporting document').getByRole('button', { name: 'Attach document' }).click()
    await expect(toast(page, 'Pick a request and a file.')).toBeVisible()
    await snap(page, 'attach blocked')
    actual('Toast "Pick a request and a file." shown')
  })

  test('TC-UI-027 My Requests shows status and days elapsed', async ({ page }) => {
    tc({ id: 'TC-UI-027', story: 'US-1.3', type: 'Functional', priority: 'P1', steps: ['Open My Requests', 'Find the new request'], expected: 'Row shows request #, type Vendor, title, status Submitted, days elapsed 0' })
    const crNumber = state.need(K('crNumber'))
    await nav(page, 'My Requests')
    const row = page.getByRole('row').filter({ hasText: crNumber })
    await expect(row).toBeVisible()
    await row.scrollIntoViewIfNeeded()
    await snap(page, 'my requests')
    const cells = (await row.getByRole('cell').allTextContents()).map((s) => s.trim())
    actual(cells.join(' | '))
    expect(cells[1]).toBe('Vendor')
    expect(cells[3]).toBe('Submitted')
    expect(cells[4]).toBe('0')
  })
})
