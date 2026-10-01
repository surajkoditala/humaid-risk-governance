# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: ui\03-assessment-workspace.ui.spec.ts >> Epics 2-7 - Analyst assessment workspace (UI) >> TC-UI-031 Finalize tab on an untouched assessment does not offer finalization
- Location: specs\ui\03-assessment-workspace.ui.spec.ts:48:7

# Error details

```
Error: Finalize must be disabled on an empty assessment

expect(received).toBe(expected) // Object.is equality

Expected: false
Received: true
```

# Page snapshot

```yaml
- generic [ref=e2]:
  - generic [ref=e4]:
    - complementary [ref=e5]:
      - generic [ref=e6]: Risk Workbench
      - navigation [ref=e11]:
        - button "Assessments" [ref=e12]
    - generic [ref=e13]:
      - banner [ref=e14]:
        - combobox [ref=e15]:
          - generic [ref=e16]: Amara Chen — Analyst
          - img [aria-hidden]: ▼
        - textbox [aria-hidden] [ref=e17]: 4fa322d3-2245-44ef-b664-1a804442db23
        - generic [ref=e18]: AC
      - main [ref=e21]:
        - generic [ref=e23]:
          - generic [ref=e24]:
            - generic [ref=e25]:
              - button "← Back to inbox" [ref=e26]
              - heading "CR-2026-00066 — [QA-E2E FINAL09251251] UI lifecycle - onboard Malta settlement vendor" [level=2] [ref=e27]
            - generic [ref=e28]: Draft
          - generic [ref=e29]:
            - tablist [ref=e31]:
              - tab "Categories" [ref=e32]
              - tab "Policy" [ref=e33]
              - tab "Extraction" [ref=e34]
              - tab "Narrative" [ref=e35]
              - tab "Scoring" [ref=e36]
              - tab "Finalize" [active] [selected] [ref=e37]
              - tab "Audit" [ref=e38]
            - tabpanel "Finalize" [ref=e39]:
              - generic [ref=e40]:
                - generic [ref=e41]:
                  - generic [ref=e42]: Readiness
                  - generic [ref=e43]: US-6.3 — everything must be reviewed before this can move on.
                - generic [ref=e44]:
                  - paragraph [ref=e45]: Ready to finalize.
                  - generic [ref=e46]:
                    - button "Finalize" [ref=e47]
                    - button "Route to committee" [disabled]
      - contentinfo [ref=e48]: © 2026 HumAId Risk Governance. All rights reserved.
  - region "Notifications alt+T"
```

# Test source

```ts
  1   | import { expect, test, type Page } from '@playwright/test'
  2   | import { actual, defect, snap, tc } from '../../lib/harness'
  3   | import { card, choose, enterApp, nav, toast, USERS } from '../../lib/app'
  4   | import { state } from '../../lib/state'
  5   | 
  6   | const K = (k: string) => `ui.${k}`
  7   | const AI_TIMEOUT = 180_000
  8   | 
  9   | async function openWorkspace(page: Page) {
  10  |   const crNumber = state.need(K('crNumber'))
  11  |   await enterApp(page, USERS.analyst)
  12  |   await nav(page, 'Assessments')
  13  |   const row = page.getByRole('row').filter({ hasText: crNumber })
  14  |   await expect(row).toBeVisible()
  15  |   await row.getByRole('button', { name: 'Open' }).click()
  16  |   await expect(page.getByRole('tab', { name: 'Categories' })).toBeVisible()
  17  |   return crNumber
  18  | }
  19  | 
  20  | async function tab(page: Page, name: string) {
  21  |   await page.getByRole('tab', { name }).click()
  22  |   await expect(page.getByRole('tab', { name })).toHaveAttribute('aria-selected', 'true')
  23  | }
  24  | 
  25  | /** Category names currently mapped (active) - read from the Mapped categories card. */
  26  | async function mappedCategories(page: Page) {
  27  |   await tab(page, 'Categories')
  28  |   const rows = card(page, 'Mapped categories').locator('.rounded-md.border p.text-sm.font-medium')
  29  |   return (await rows.allTextContents()).map((s) => s.trim())
  30  | }
  31  | 
  32  | test.describe('Epics 2-7 - Analyst assessment workspace (UI)', () => {
  33  |   test.describe.configure({ timeout: 300_000 })
  34  | 
  35  |   test('TC-UI-030 Analyst inbox lists the request; workspace opens with seven tabs', async ({ page }) => {
  36  |     tc({ id: 'TC-UI-030', story: 'US-6.3', type: 'Functional', priority: 'P1', steps: ['Act as Amara Chen (Analyst)', 'Open Assessments', 'Click Open on the new request'], expected: 'Workspace header shows CR number + title; tabs Categories, Policy, Extraction, Narrative, Scoring, Finalize, Audit; status InProgress' })
  37  |     await enterApp(page, USERS.analyst)
  38  |     await nav(page, 'Assessments')
  39  |     await snap(page, 'analyst inbox')
  40  |     const crNumber = await openWorkspace(page)
  41  |     const tabs = (await page.getByRole('tab').allTextContents()).map((s) => s.trim())
  42  |     await snap(page, 'workspace opened')
  43  |     actual(`${crNumber} opened; tabs: ${tabs.join(', ')}`)
  44  |     expect(tabs).toEqual(['Categories', 'Policy', 'Extraction', 'Narrative', 'Scoring', 'Finalize', 'Audit'])
  45  |     await expect(page.getByRole('heading', { name: new RegExp(crNumber) })).toBeVisible()
  46  |   })
  47  | 
  48  |   test('TC-UI-031 Finalize tab on an untouched assessment does not offer finalization', async ({ page }) => {
  49  |     tc({ id: 'TC-UI-031', story: 'US-6.3', type: 'Negative', priority: 'P1', steps: ['Open the workspace before any category, policy or narrative work', 'Open the Finalize tab'], expected: 'Outstanding work is listed and the Finalize button is disabled' })
  50  |     defect('DEF-001')
  51  |     await openWorkspace(page)
  52  |     await tab(page, 'Finalize')
  53  |     const readyCard = card(page, 'Readiness')
  54  |     await expect(readyCard).toBeVisible()
  55  |     await page.waitForTimeout(1500)
  56  |     await snap(page, 'finalize tab untouched')
  57  |     const text = (await readyCard.textContent()) || ''
  58  |     const finalizeEnabled = await readyCard.getByRole('button', { name: 'Finalize' }).isEnabled()
  59  |     actual(`Readiness card says "${text.includes('Ready to finalize') ? 'Ready to finalize.' : 'not ready'}"; Finalize button enabled = ${finalizeEnabled} (nothing has been mapped, reviewed or scored). Not clicked, so the flow can continue.`)
> 60  |     expect(finalizeEnabled, 'Finalize must be disabled on an empty assessment').toBe(false)
      |                                                                                 ^ Error: Finalize must be disabled on an empty assessment
  61  |   })
  62  | 
  63  |   test('TC-UI-032 Propose categories with AI - FFIEC categories with citations', async ({ page }) => {
  64  |     tc({ id: 'TC-UI-032', story: 'US-2.1', type: 'Functional', priority: 'P1', steps: ['Categories tab -> Propose with AI', 'Wait for "AI proposal saved"'], expected: 'Mapped categories list shows FFIEC categories, each labelled "AI - <citation>"' })
  65  |     await openWorkspace(page)
  66  |     await page.getByRole('button', { name: 'Propose with AI' }).click()
  67  |     await expect(page.getByRole('button', { name: 'Proposing…' })).toBeVisible()
  68  |     await snap(page, 'proposing')
  69  |     await expect(toast(page, 'AI proposal saved')).toBeVisible({ timeout: AI_TIMEOUT })
  70  |     await expect(card(page, 'Mapped categories').getByText(/^AI — /).first()).toBeVisible()
  71  |     await snap(page, 'ai proposal')
  72  |     const cats = await mappedCategories(page)
  73  |     const citations = await card(page, 'Mapped categories').getByText(/^AI — /).allTextContents()
  74  |     actual(`AI mapped: ${cats.join(', ')}; citations: ${citations.join(' | ')}`)
  75  |     expect(cats.length).toBeGreaterThan(0)
  76  |     for (const c of cats) expect(['Products & Services', 'Customers & Entities', 'Geographic Locations', 'Delivery Channels']).toContain(c)
  77  |     expect(citations.every((c) => /FFIEC/.test(c))).toBeTruthy()
  78  |   })
  79  | 
  80  |   test('TC-UI-033 Adding or removing a category requires a reason', async ({ page }) => {
  81  |     tc({ id: 'TC-UI-033', story: 'US-2.2 / US-6.1', type: 'Negative', priority: 'P1', steps: ['Select "Geographic Locations" in Add a category, leave Reason blank, click Add', 'Click Remove on a mapped category with Reason blank', 'Enter a reason and Add Geographic Locations'], expected: 'Both blank-reason attempts blocked with "A reason is required..."; with a reason the category is added as "Analyst added"' })
  82  |     await openWorkspace(page)
  83  |     const mapped = card(page, 'Mapped categories')
  84  |     await choose(page, mapped.getByRole('combobox'), 'Geographic Locations')
  85  |     await mapped.getByRole('button', { name: 'Add', exact: true }).click()
  86  |     await expect(toast(page, /reason is required/)).toBeVisible()
  87  |     await snap(page, 'add blocked without reason')
  88  |     await mapped.getByRole('button', { name: 'Remove' }).first().click()
  89  |     await expect(toast(page, /reason is required/).last()).toBeVisible()
  90  |     await snap(page, 'remove blocked without reason')
  91  |     const before = await mappedCategories(page)
  92  |     const already = before.includes('Geographic Locations')
  93  |     if (!already) {
  94  |       await choose(page, mapped.getByRole('combobox'), 'Geographic Locations')
  95  |       await mapped.getByPlaceholder('Reason').fill('Vendor domiciled in Malta - geographic exposure (QA)')
  96  |       await mapped.getByRole('button', { name: 'Add', exact: true }).click()
  97  |       await expect(mapped.locator('p.text-sm.font-medium').filter({ hasText: 'Geographic Locations' })).toBeVisible()
  98  |     }
  99  |     // Delivery Channels is the other primary category for a vendor onboarding (CLAUDE.md mapping).
  100 |     const now = await mappedCategories(page)
  101 |     if (!now.includes('Delivery Channels')) {
  102 |       await choose(page, mapped.getByRole('combobox'), 'Delivery Channels')
  103 |       await mapped.getByPlaceholder('Reason').fill('API integration is a non-face-to-face delivery channel (QA)')
  104 |       await mapped.getByRole('button', { name: 'Add', exact: true }).click()
  105 |       await expect(mapped.locator('p.text-sm.font-medium').filter({ hasText: 'Delivery Channels' })).toBeVisible()
  106 |     }
  107 |     await snap(page, 'categories after analyst overrides')
  108 |     const after = await mappedCategories(page)
  109 |     state.set(K('cats'), after)
  110 |     const labels = await mapped.locator('p.text-xs.text-muted-foreground').allTextContents()
  111 |     actual(`blank reason blocked for add and remove; mapped now: ${after.join(', ')}; sources: ${labels.join(' | ')}`)
  112 |     expect(after).toContain('Geographic Locations')
  113 |     expect(labels.some((l) => l === 'Analyst added')).toBeTruthy()
  114 |   })
  115 | 
  116 |   test('TC-UI-034 Policy search, relied-upon decisions per category', async ({ page }) => {
  117 |     tc({ id: 'TC-UI-034', story: 'US-3.1 / US-3.2', type: 'Functional', priority: 'P1', steps: ['Policy tab', 'For each mapped category: pick it in the filter, search "risk", mark a passage not used before as "Relied upon"', 'Search nonsense text'], expected: 'Results show section reference + passage; each decision toast "Marked ReliedUpon" and appears under Reliance decisions recorded; nonsense -> "No matches."' })
  118 |     await openWorkspace(page)
  119 |     await tab(page, 'Policy')
  120 |     const cats: string[] = state.need(K('cats'))
  121 |     const searchCard = card(page, 'Search the policy corpus')
  122 |     const used = new Set<string>()
  123 |     for (const c of cats) {
  124 |       await choose(page, searchCard.getByRole('combobox'), c)
  125 |       await searchCard.getByPlaceholder(/beneficial ownership/).fill('risk')
  126 |       await Promise.all([
  127 |         page.waitForResponse((r) => r.url().includes('/api/PolicyResearch/Search')),
  128 |         searchCard.getByRole('button', { name: 'Search' }).click(),
  129 |       ])
  130 |       await page.waitForTimeout(300)
  131 |       const results = searchCard.locator('.rounded-md.border.p-3')
  132 |       await expect(results.first()).toBeVisible()
  133 |       const n = await results.count()
  134 |       let clicked = false
  135 |       for (let i = 0; i < n && !clicked; i++) {
  136 |         const ref = (await results.nth(i).locator('p').first().textContent()) || ''
  137 |         if (used.has(ref)) continue
  138 |         used.add(ref)
  139 |         await results.nth(i).getByRole('button', { name: 'Relied upon' }).click()
  140 |         await expect(toast(page, 'Marked ReliedUpon').last()).toBeVisible()
  141 |         clicked = true
  142 |       }
  143 |       await snap(page, `relied upon for ${c}`)
  144 |     }
  145 |     await searchCard.getByPlaceholder(/beneficial ownership/).fill('zzqxv plorbnak')
  146 |     await searchCard.getByRole('button', { name: 'Search' }).click()
  147 |     await expect(searchCard.getByText('No matches.')).toBeVisible()
  148 |     const recorded = await card(page, 'Reliance decisions recorded').locator('.flex.items-center.justify-between').count()
  149 |     await snap(page, 'reliance recorded + no matches')
  150 |     actual(`${used.size} distinct passages relied upon across ${cats.length} categories; ${recorded} decisions listed; nonsense query -> "No matches."`)
  151 |     expect(recorded).toBeGreaterThanOrEqual(cats.length)
  152 |   })
  153 | 
  154 |   test('TC-UI-035 Search results show source document, version and effective date', async ({ page }) => {
  155 |     tc({ id: 'TC-UI-035', story: 'US-3.1', type: 'Functional', priority: 'P2', steps: ['Policy tab -> search "beneficial ownership"', 'Inspect a result'], expected: 'Each result shows its relevance rationale, a link to the source document and its effective date' })
  156 |     defect('DEF-026')
  157 |     await openWorkspace(page)
  158 |     await tab(page, 'Policy')
  159 |     const searchCard = card(page, 'Search the policy corpus')
  160 |     await searchCard.getByPlaceholder(/beneficial ownership/).fill('beneficial ownership')
```