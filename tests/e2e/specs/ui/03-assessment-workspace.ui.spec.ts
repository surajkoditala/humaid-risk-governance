import { expect, test, type Page } from '@playwright/test'
import { actual, defect, snap, tc } from '../../lib/harness'
import { card, choose, enterApp, nav, toast, USERS } from '../../lib/app'
import { state } from '../../lib/state'

const K = (k: string) => `ui.${k}`
const AI_TIMEOUT = 180_000

async function openWorkspace(page: Page) {
  const crNumber = state.need(K('crNumber'))
  await enterApp(page, USERS.analyst)
  await nav(page, 'Assessments')
  const row = page.getByRole('row').filter({ hasText: crNumber })
  await expect(row).toBeVisible()
  await row.getByRole('button', { name: 'Open' }).click()
  await expect(page.getByRole('tab', { name: 'Categories' })).toBeVisible()
  return crNumber
}

async function tab(page: Page, name: string) {
  await page.getByRole('tab', { name }).click()
  await expect(page.getByRole('tab', { name })).toHaveAttribute('aria-selected', 'true')
}

/** Category names currently mapped (active) - read from the Mapped categories card. */
async function mappedCategories(page: Page) {
  await tab(page, 'Categories')
  const rows = card(page, 'Mapped categories').locator('.rounded-md.border p.text-sm.font-medium')
  return (await rows.allTextContents()).map((s) => s.trim())
}

test.describe('Epics 2-7 - Analyst assessment workspace (UI)', () => {
  test.describe.configure({ timeout: 300_000 })

  test('TC-UI-030 Analyst inbox lists the request; workspace opens with seven tabs', async ({ page }) => {
    tc({ id: 'TC-UI-030', story: 'US-6.3', type: 'Functional', priority: 'P1', steps: ['Act as Amara Chen (Analyst)', 'Open Assessments', 'Click Open on the new request'], expected: 'Workspace header shows CR number + title; tabs Categories, Policy, Extraction, Narrative, Scoring, Finalize, Audit; status InProgress' })
    await enterApp(page, USERS.analyst)
    await nav(page, 'Assessments')
    await snap(page, 'analyst inbox')
    const crNumber = await openWorkspace(page)
    const tabs = (await page.getByRole('tab').allTextContents()).map((s) => s.trim())
    await snap(page, 'workspace opened')
    actual(`${crNumber} opened; tabs: ${tabs.join(', ')}`)
    expect(tabs).toEqual(['Categories', 'Policy', 'Extraction', 'Narrative', 'Scoring', 'Finalize', 'Audit'])
    await expect(page.getByRole('heading', { name: new RegExp(crNumber) })).toBeVisible()
  })

  test('TC-UI-031 Finalize tab on an untouched assessment does not offer finalization', async ({ page }) => {
    tc({ id: 'TC-UI-031', story: 'US-6.3', type: 'Negative', priority: 'P1', steps: ['Open the workspace before any category, policy or narrative work', 'Open the Finalize tab'], expected: 'Outstanding work is listed and the Finalize button is disabled' })
    defect('DEF-001')
    await openWorkspace(page)
    await tab(page, 'Finalize')
    const readyCard = card(page, 'Readiness')
    await expect(readyCard).toBeVisible()
    await page.waitForTimeout(1500)
    await snap(page, 'finalize tab untouched')
    const text = (await readyCard.textContent()) || ''
    const finalizeEnabled = await readyCard.getByRole('button', { name: 'Finalize' }).isEnabled()
    actual(`Readiness card says "${text.includes('Ready to finalize') ? 'Ready to finalize.' : 'not ready'}"; Finalize button enabled = ${finalizeEnabled} (nothing has been mapped, reviewed or scored). Not clicked, so the flow can continue.`)
    expect(finalizeEnabled, 'Finalize must be disabled on an empty assessment').toBe(false)
  })

  test('TC-UI-032 Propose categories with AI - FFIEC categories with citations', async ({ page }) => {
    tc({ id: 'TC-UI-032', story: 'US-2.1', type: 'Functional', priority: 'P1', steps: ['Categories tab -> Propose with AI', 'Wait for "AI proposal saved"'], expected: 'Mapped categories list shows FFIEC categories, each labelled "AI - <citation>"' })
    await openWorkspace(page)
    await page.getByRole('button', { name: 'Propose with AI' }).click()
    await expect(page.getByRole('button', { name: 'Proposing…' })).toBeVisible()
    await snap(page, 'proposing')
    await expect(toast(page, 'AI proposal saved')).toBeVisible({ timeout: AI_TIMEOUT })
    await expect(card(page, 'Mapped categories').getByText(/^AI — /).first()).toBeVisible()
    await snap(page, 'ai proposal')
    const cats = await mappedCategories(page)
    const citations = await card(page, 'Mapped categories').getByText(/^AI — /).allTextContents()
    actual(`AI mapped: ${cats.join(', ')}; citations: ${citations.join(' | ')}`)
    expect(cats.length).toBeGreaterThan(0)
    for (const c of cats) expect(['Products & Services', 'Customers & Entities', 'Geographic Locations', 'Delivery Channels']).toContain(c)
    expect(citations.every((c) => /FFIEC/.test(c))).toBeTruthy()
  })

  test('TC-UI-033 Adding or removing a category requires a reason', async ({ page }) => {
    tc({ id: 'TC-UI-033', story: 'US-2.2 / US-6.1', type: 'Negative', priority: 'P1', steps: ['Select "Geographic Locations" in Add a category, leave Reason blank, click Add', 'Click Remove on a mapped category with Reason blank', 'Enter a reason and Add Geographic Locations'], expected: 'Both blank-reason attempts blocked with "A reason is required..."; with a reason the category is added as "Analyst added"' })
    await openWorkspace(page)
    const mapped = card(page, 'Mapped categories')
    await choose(page, mapped.getByRole('combobox'), 'Geographic Locations')
    await mapped.getByRole('button', { name: 'Add', exact: true }).click()
    await expect(toast(page, /reason is required/)).toBeVisible()
    await snap(page, 'add blocked without reason')
    await mapped.getByRole('button', { name: 'Remove' }).first().click()
    await expect(toast(page, /reason is required/).last()).toBeVisible()
    await snap(page, 'remove blocked without reason')
    const before = await mappedCategories(page)
    const already = before.includes('Geographic Locations')
    if (!already) {
      await choose(page, mapped.getByRole('combobox'), 'Geographic Locations')
      await mapped.getByPlaceholder('Reason').fill('Vendor domiciled in Malta - geographic exposure (QA)')
      await mapped.getByRole('button', { name: 'Add', exact: true }).click()
      await expect(mapped.locator('p.text-sm.font-medium').filter({ hasText: 'Geographic Locations' })).toBeVisible()
    }
    // Delivery Channels is the other primary category for a vendor onboarding (CLAUDE.md mapping).
    const now = await mappedCategories(page)
    if (!now.includes('Delivery Channels')) {
      await choose(page, mapped.getByRole('combobox'), 'Delivery Channels')
      await mapped.getByPlaceholder('Reason').fill('API integration is a non-face-to-face delivery channel (QA)')
      await mapped.getByRole('button', { name: 'Add', exact: true }).click()
      await expect(mapped.locator('p.text-sm.font-medium').filter({ hasText: 'Delivery Channels' })).toBeVisible()
    }
    await snap(page, 'categories after analyst overrides')
    const after = await mappedCategories(page)
    state.set(K('cats'), after)
    const labels = await mapped.locator('p.text-xs.text-muted-foreground').allTextContents()
    actual(`blank reason blocked for add and remove; mapped now: ${after.join(', ')}; sources: ${labels.join(' | ')}`)
    expect(after).toContain('Geographic Locations')
    expect(labels.some((l) => l === 'Analyst added')).toBeTruthy()
  })

  test('TC-UI-034 Policy search, relied-upon decisions per category', async ({ page }) => {
    tc({ id: 'TC-UI-034', story: 'US-3.1 / US-3.2', type: 'Functional', priority: 'P1', steps: ['Policy tab', 'For each mapped category: pick it in the filter, search "risk", mark a passage not used before as "Relied upon"', 'Search nonsense text'], expected: 'Results show section reference + passage; each decision toast "Marked ReliedUpon" and appears under Reliance decisions recorded; nonsense -> "No matches."' })
    await openWorkspace(page)
    await tab(page, 'Policy')
    const cats: string[] = state.need(K('cats'))
    const searchCard = card(page, 'Search the policy corpus')
    const used = new Set<string>()
    for (const c of cats) {
      await choose(page, searchCard.getByRole('combobox'), c)
      await searchCard.getByPlaceholder(/beneficial ownership/).fill('risk')
      await Promise.all([
        page.waitForResponse((r) => r.url().includes('/api/PolicyResearch/Search')),
        searchCard.getByRole('button', { name: 'Search' }).click(),
      ])
      await page.waitForTimeout(300)
      const results = searchCard.locator('.rounded-md.border.p-3')
      await expect(results.first()).toBeVisible()
      const n = await results.count()
      let clicked = false
      for (let i = 0; i < n && !clicked; i++) {
        const ref = (await results.nth(i).locator('p').first().textContent()) || ''
        if (used.has(ref)) continue
        used.add(ref)
        await results.nth(i).getByRole('button', { name: 'Relied upon' }).click()
        await expect(toast(page, 'Marked ReliedUpon').last()).toBeVisible()
        clicked = true
      }
      await snap(page, `relied upon for ${c}`)
    }
    await searchCard.getByPlaceholder(/beneficial ownership/).fill('zzqxv plorbnak')
    await searchCard.getByRole('button', { name: 'Search' }).click()
    await expect(searchCard.getByText('No matches.')).toBeVisible()
    const recorded = await card(page, 'Reliance decisions recorded').locator('.flex.items-center.justify-between').count()
    await snap(page, 'reliance recorded + no matches')
    actual(`${used.size} distinct passages relied upon across ${cats.length} categories; ${recorded} decisions listed; nonsense query -> "No matches."`)
    expect(recorded).toBeGreaterThanOrEqual(cats.length)
  })

  test('TC-UI-035 Search results show source document, version and effective date', async ({ page }) => {
    tc({ id: 'TC-UI-035', story: 'US-3.1', type: 'Functional', priority: 'P2', steps: ['Policy tab -> search "beneficial ownership"', 'Inspect a result'], expected: 'Each result shows its relevance rationale, a link to the source document and its effective date' })
    defect('DEF-026')
    await openWorkspace(page)
    await tab(page, 'Policy')
    const searchCard = card(page, 'Search the policy corpus')
    await searchCard.getByPlaceholder(/beneficial ownership/).fill('beneficial ownership')
    await searchCard.getByRole('button', { name: 'Search' }).click()
    const first = searchCard.locator('.rounded-md.border.p-3').first()
    await expect(first).toBeVisible()
    await snap(page, 'search result detail')
    const links = await first.getByRole('link').count()
    const hasDate = /20\d\d/.test((await first.textContent()) || '')
    actual(`result shows section ref + passage text only; links to source: ${links}; effective date shown: ${hasDate}; relevance rationale: none (API returns sourceUrl/effectiveDate but the UI drops them)`)
    expect.soft(links, 'link to source document').toBeGreaterThan(0)
    expect.soft(hasDate, 'effective date visible').toBe(true)
  })

  test('TC-UI-036 AI extraction runs against the uploaded document content', async ({ page }) => {
    tc({ id: 'TC-UI-036', story: 'US-4.1', type: 'Functional', priority: 'P1', steps: ['Extraction tab', 'Click "Extract with AI" on vendor-due-diligence.pdf (v1)', 'Wait for "Extraction complete"', 'Read extracted fields'], expected: 'Fields populated from the PDF text (vendor QuickPay, jurisdiction Malta, PII scope) with source excerpts; low-confidence fields flagged "Needs review"' })
    defect('DEF-020')
    await openWorkspace(page)
    await tab(page, 'Extraction')
    const att = card(page, 'Attachments')
    const pdfRow = att.locator('.rounded-md.border').filter({ hasText: 'vendor-due-diligence.pdf' }).first()
    await expect(pdfRow).toBeVisible()
    await snap(page, 'attachments listed')
    await pdfRow.getByRole('button', { name: 'Extract with AI' }).click()
    await expect(toast(page, 'Extraction complete').or(att.locator('.bg-amber-50'))).toBeVisible({ timeout: AI_TIMEOUT })
    const fieldsCard = card(page, 'Extracted fields')
    await page.waitForTimeout(4000)
    await snap(page, 'extracted fields')
    const text = (await fieldsCard.textContent()) || ''
    const keys = await fieldsCard.locator('span.text-sm.font-medium').allTextContents()
    const needsReview = await fieldsCard.getByText('Needs review').count()
    state.set(K('fieldKey'), keys[0])
    actual(`${keys.length} fields (${keys.join(', ')}); ${needsReview} flagged "Needs review"; mentions Malta: ${/Malta/.test(text)}; mentions QuickPay: ${/QuickPay/.test(text)}. The UI sends documentText = attachment.fileName, so the model only ever sees "vendor-due-diligence.pdf".`)
    expect(keys.length).toBeGreaterThan(0)
    expect.soft(text, 'values should come from the document body').toMatch(/Malta/)
  })

  test('TC-UI-037 Correct an extracted field', async ({ page }) => {
    tc({ id: 'TC-UI-037', story: 'US-4.2', type: 'Functional', priority: 'P2', steps: ['Extraction tab', 'Type a corrected value for the first field', 'Click Correct'], expected: 'Toast "Field corrected"; field shows the new value with source AnalystCorrected; original retained in audit' })
    let key: string | undefined = state.get(K('fieldKey'))
    if (!key) {
      // UI extraction produced nothing (DEF-020). Seed fields through the API with the real document
      // text so the correction UI itself can still be exercised.
      const crNumber = state.need(K('crNumber'))
      const all = await (await page.request.get('/api/ChangeRequest')).json()
      const cr = all.data.find((r: any) => r.requestNumber === crNumber)
      const atts = await (await page.request.get(`/api/ChangeRequest/${cr.id}/Attachments`)).json()
      const r = await page.request.post('/api/DocumentExtraction/Extract', { data: { changeRequestId: cr.id, attachmentId: atts.data[0].id, changeType: 'Vendor', documentText: 'Vendor name: QuickPay Processing Ltd. Jurisdiction: Malta. Data access scope: cardholder PII and settlement files.' }, timeout: 180_000 })
      key = (await r.json()).data?.[0]?.fieldKey
      test.skip(!key, 'No extracted fields available to correct')
    }
    await openWorkspace(page)
    await tab(page, 'Extraction')
    const field = card(page, 'Extracted fields').locator('.rounded-md.border.p-3').filter({ hasText: key! }).first()
    await field.getByPlaceholder('Corrected value').fill('Malta (QA corrected)')
    await field.getByRole('button', { name: 'Correct' }).click()
    const t = page.locator('[data-sonner-toast]').last()
    await expect(t).toBeVisible()
    const msg = (await t.textContent()) || ''
    await page.waitForTimeout(800)
    await snap(page, 'after correct')
    const badges = await field.locator('[data-slot="badge"]').allTextContents()
    actual(`clicked Correct on ${key} with "Malta (QA corrected)" -> toast "${msg}"; badges: ${badges.join(', ')}. The UI request carries no actorUserId (and a hard-coded reason "Analyst correction"), so the API rejects it; the same correction via API with an actor id succeeds (TC-API-051).`)
    defect('DEF-033')
    defect('DEF-027')
    expect.soft(msg, 'correction should be saved').toMatch(/Field corrected/)
    expect.soft(await field.getByPlaceholder(/reason/i).count(), 'a reason input should exist for material corrections').toBeGreaterThan(0)
  })

  test('TC-UI-038 Draft narratives with AI; labelled pending review', async ({ page }) => {
    tc({ id: 'TC-UI-038', story: 'US-5.1', type: 'Functional', priority: 'P1', steps: ['Narrative tab', 'Click "Draft with AI" on each category card'], expected: 'Each card shows AI narrative text and the badge "AI-drafted - pending analyst review"' })
    await openWorkspace(page)
    await tab(page, 'Narrative')
    const cats: string[] = state.need(K('cats'))
    for (const c of cats) {
      const cc = card(page, c)
      await cc.getByRole('button', { name: /Draft with AI|Regenerate with AI/ }).click()
      await expect(cc.getByText('AI-drafted — pending analyst review')).toBeVisible({ timeout: AI_TIMEOUT })
    }
    await snap(page, 'narratives drafted')
    const n = await page.getByText('AI-drafted — pending analyst review').count()
    actual(`${n} of ${cats.length} sections drafted and labelled "AI-drafted — pending analyst review"`)
    expect(n).toBe(cats.length)
  })

  test('TC-UI-039 Finalize is blocked while narratives are AI-drafted', async ({ page }) => {
    tc({ id: 'TC-UI-039', story: 'US-5.1 / US-6.3', type: 'Negative', priority: 'P1', steps: ['Finalize tab'], expected: '"Narrative not reviewed: <categories>" shown; Finalize and Route disabled' })
    await openWorkspace(page)
    await tab(page, 'Finalize')
    const rc = card(page, 'Readiness')
    await expect(rc.getByText(/Narrative not reviewed/)).toBeVisible()
    await snap(page, 'blocked by ai drafts')
    actual(`${(await rc.getByText(/Narrative not reviewed/).textContent())?.trim()}; Finalize enabled=${await rc.getByRole('button', { name: 'Finalize' }).isEnabled()}`)
    await expect(rc.getByRole('button', { name: 'Finalize' })).toBeDisabled()
    await expect(rc.getByRole('button', { name: 'Route to committee' })).toBeDisabled()
  })

  test('TC-UI-040 Narrative edit needs a reason; accept-as-is and edit clear the AI label', async ({ page }) => {
    tc({ id: 'TC-UI-040', story: 'US-6.1', type: 'Negative', priority: 'P1', steps: ['Narrative tab', 'Category #1: type new text, leave reason blank, Save edit', 'Enter a reason, Save edit', 'Other categories: Accept as-is'], expected: 'Blank reason blocked ("New text and a reason are both required."); edited card -> "Analyst edited"; accepted -> "Analyst reviewed"' })
    await openWorkspace(page)
    await tab(page, 'Narrative')
    const cats: string[] = state.need(K('cats'))
    const first = card(page, cats[0])
    await first.getByPlaceholder('Edited narrative text').fill('QA analyst narrative: onboarding a Malta-domiciled settlement processor with API access to cardholder PII. EDD and annual audit rights required.')
    await first.getByRole('button', { name: 'Save edit' }).click()
    await expect(toast(page, 'New text and a reason are both required.')).toBeVisible()
    await snap(page, 'edit blocked without reason')
    await first.getByPlaceholder('Reason for edit').fill('Added EDD requirement and tightened wording (QA)')
    await first.getByRole('button', { name: 'Save edit' }).click()
    await expect(first.getByText('Analyst edited')).toBeVisible()
    for (const c of cats.slice(1)) {
      await card(page, c).getByRole('button', { name: 'Accept as-is' }).click()
      await expect(card(page, c).getByText('Analyst reviewed')).toBeVisible()
    }
    await snap(page, 'narratives reviewed')
    actual(`${cats[0]} = Analyst edited; ${cats.slice(1).join(', ')} = Analyst reviewed`)
  })

  test('TC-UI-041 Calculate scores - residual shown and always > 0', async ({ page }) => {
    tc({ id: 'TC-UI-041', story: 'US-7.1', type: 'Functional', priority: 'P1', steps: ['Scoring tab', 'Category #1: inherent 5, effectiveness 1 -> Calculate', 'Other categories: inherent 3, effectiveness 0.5 -> Calculate'], expected: 'Inherent, Mitigation and Residual shown; residual = inherent - effectiveness x mitigation; even at full effectiveness residual > 0' })
    await openWorkspace(page)
    await tab(page, 'Scoring')
    const cats: string[] = state.need(K('cats'))
    const out: string[] = []
    for (const [i, c] of cats.entries()) {
      const cc = card(page, c)
      const [inh, eff] = i === 0 ? ['5', '1'] : ['3', '0.5']
      await cc.getByRole('spinbutton').nth(0).fill(inh)
      await cc.getByRole('spinbutton').nth(1).fill(eff)
      await cc.getByRole('button', { name: 'Calculate' }).click()
      await expect(cc.getByText(/Residual:/)).toBeVisible()
      const t = (await cc.locator('.flex.flex-wrap.gap-4').textContent()) || ''
      const mf = Number(t.match(/Mitigation: ([\d.]+)/)![1])
      const res = Number(t.match(/Residual: ([\d.]+)/)![1])
      out.push(`${c}: ${inh} - ${eff} x ${mf} = ${res}`)
      expect(res).toBeGreaterThan(0)
      expect(res).toBeCloseTo(Number(inh) - Number(eff) * mf, 2)
    }
    await snap(page, 'scores calculated')
    actual(out.join('; '))
  })

  test('TC-UI-042 Invalid score input shows a validation message', async ({ page }) => {
    tc({ id: 'TC-UI-042', story: 'US-7.1', type: 'Negative', priority: 'P2', steps: ['Scoring tab', 'Category #1: inherent 9 -> Calculate'], expected: 'Clear validation message ("inherent must be 1-5"); stored score unchanged' })
    defect('DEF-005')
    await openWorkspace(page)
    await tab(page, 'Scoring')
    const cats: string[] = state.need(K('cats'))
    const cc = card(page, cats[0])
    await cc.getByRole('spinbutton').nth(0).fill('9')
    await cc.getByRole('spinbutton').nth(1).fill('0.5')
    await cc.getByRole('button', { name: 'Calculate' }).click()
    const note = page.locator('.bg-amber-50').first()
    await expect(note).toBeVisible()
    await snap(page, 'invalid inherent')
    const msg = (await note.textContent()) || ''
    actual(`message shown: "${msg}"`)
    expect.soft(msg, 'should say what is wrong, not a generic failure').not.toMatch(/Failed to calculate/)
  })

  test('TC-UI-043 Score override: reason required, zero rejected, override labelled', async ({ page }) => {
    tc({ id: 'TC-UI-043', story: 'US-7.2', type: 'Negative', priority: 'P1', steps: ['Scoring tab, category #1', 'Override residual 2 with blank reason', 'Override residual 0 with a reason', 'Override residual 2.5 with a reason'], expected: 'Blank reason blocked; 0 rejected ("must be greater than zero"); valid override shows "Analyst override" badge' })
    await openWorkspace(page)
    await tab(page, 'Scoring')
    const cats: string[] = state.need(K('cats'))
    const cc = card(page, cats[0])
    const ov = cc.getByRole('spinbutton').nth(2)
    await ov.fill('2')
    await cc.getByRole('button', { name: 'Override' }).click()
    await expect(toast(page, 'New residual rating and a reason are both required.')).toBeVisible()
    await snap(page, 'override blocked no reason')
    await ov.fill('0')
    await cc.getByPlaceholder('Reason').fill('QA zero test')
    await cc.getByRole('button', { name: 'Override' }).click()
    await expect(toast(page, /greater than zero/)).toBeVisible()
    await snap(page, 'override zero rejected')
    await ov.fill('2.5')
    await cc.getByPlaceholder('Reason').fill('Vendor had prior regulatory findings (QA)')
    await cc.getByRole('button', { name: 'Override' }).click()
    await expect(cc.getByText('Analyst override')).toBeVisible()
    await snap(page, 'override applied')
    actual(`blank reason blocked; 0 rejected; 2.5 saved with "Analyst override" badge; residual now ${(await cc.locator('.flex.flex-wrap.gap-4').textContent())?.match(/Residual: ([\d.]+)/)?.[1]}`)
  })

  test('TC-UI-044 Finalize and route to committee', async ({ page }) => {
    tc({ id: 'TC-UI-044', story: 'US-6.3 / US-8.1', type: 'E2E', priority: 'P1', steps: ['Finalize tab: expect "Ready to finalize."', 'Click Finalize', 'Click Route to committee'], expected: 'Toasts "Assessment finalized" and "Routed to committee"; header badge Finalized; Finalize button reads "Finalized"' })
    await openWorkspace(page)
    await tab(page, 'Finalize')
    const rc = card(page, 'Readiness')
    await expect(rc.getByText('Ready to finalize.')).toBeVisible()
    await snap(page, 'ready to finalize')
    await rc.getByRole('button', { name: 'Finalize' }).click()
    await expect(toast(page, 'Assessment finalized')).toBeVisible()
    await expect(rc.getByRole('button', { name: 'Finalized' })).toBeVisible()
    await rc.getByRole('button', { name: 'Route to committee' }).click()
    await expect(toast(page, 'Routed to committee')).toBeVisible()
    await snap(page, 'finalized and routed')
    const badge = await page.locator('[data-slot="badge"]').first().textContent()
    actual(`finalized + routed; header status badge "${badge}"`)
  })

  test('TC-UI-045 Finalized assessment is read-only in the workspace', async ({ page }) => {
    tc({ id: 'TC-UI-045', story: 'US-6.3', type: 'Negative', priority: 'P1', steps: ['Re-open the finalized workspace', 'Check Propose / Add / Save edit / Calculate / Override controls'], expected: 'Editing controls disabled or hidden once finalized' })
    defect('DEF-007')
    await openWorkspace(page)
    const propose = await page.getByRole('button', { name: 'Propose with AI' }).isEnabled()
    await tab(page, 'Scoring')
    const calc = await page.getByRole('button', { name: 'Calculate' }).first().isEnabled()
    await snap(page, 'finalized scoring tab still editable')
    actual(`after finalize: "Propose with AI" enabled=${propose}, "Calculate" enabled=${calc}`)
    expect.soft(propose).toBe(false)
    expect.soft(calc).toBe(false)
  })

  test('TC-UI-046 Audit tab reconstructs every AI output and human decision with reasons', async ({ page }) => {
    tc({ id: 'TC-UI-046', story: 'US-9.1 / US-6.2', type: 'Functional', priority: 'P1', steps: ['Audit tab'], expected: 'Chronological list including ChangeRequest.Submitted, Attachment.Uploaded, CategoryMapping (AI + overrides with reasons), NarrativeSection, RiskScore Calculated/Overridden, Assessment.Finalized, routing; actor names shown; export available' })
    await openWorkspace(page)
    await tab(page, 'Audit')
    const ac = card(page, 'Audit trail')
    await expect(ac.locator('.border-b').first()).toBeVisible()
    await snap(page, 'audit trail')
    const lines = (await ac.locator('.border-b').allTextContents()).map((s) => s.replace(/\s+/g, ' ').trim())
    const text = lines.join('\n')
    const exportBtn = await page.getByRole('main').getByRole('button', { name: /export|download/i }).count()
    actual(`${lines.length} events; includes reasons "geographic exposure": ${/geographic exposure/.test(text)}, "EDD": ${/EDD/.test(text)}, override: ${/Overrid/.test(text)}; export button: ${exportBtn > 0}`)
    for (const needle of ['ChangeRequest.', 'Attachment.', 'CategoryMapping.', 'NarrativeSection.', 'RiskScore.', 'Assessment.']) expect(text).toContain(needle)
    expect(text).toMatch(/Amara Chen/)
    defect('DEF-028')
    expect.soft(exportBtn, 'US-6.2 / US-9.1: examiner export (PDF or equivalent)').toBeGreaterThan(0)
    if (exportBtn) {
      const [dl] = await Promise.all([page.waitForEvent('download', { timeout: 60_000 }), page.getByRole('main').getByRole('button', { name: /export|download/i }).first().click()])
      const file = test.info().outputPath(dl.suggestedFilename())
      await dl.saveAs(file)
      const fs = await import('node:fs')
      const head = fs.readFileSync(file).subarray(0, 5).toString()
      const size = fs.statSync(file).size
      const ev = (await import('node:path')).join(__dirname, '..', '..', 'evidence', 'ui-desktop', `TC-UI-046_03_${dl.suggestedFilename()}`)
      fs.copyFileSync(file, ev)
      await test.info().attach('evidence:exported audit pdf', { path: ev, contentType: 'application/pdf' })
      actual(`Export PDF downloaded "${dl.suggestedFilename()}" (${size} bytes, header ${head})`)
      expect(head).toBe('%PDF-')
    }
  })
})
