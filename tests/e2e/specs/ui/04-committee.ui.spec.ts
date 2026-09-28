import { expect, test, type Page } from '@playwright/test'
import { actual, defect, snap, tc } from '../../lib/harness'
import { card, choose, enterApp, nav, toast, USERS } from '../../lib/app'
import { state } from '../../lib/state'

const K = (k: string) => `ui.${k}`

async function openVotePanel(page: Page, member: string) {
  const crNumber = state.need(K('crNumber'))
  await enterApp(page, member)
  await nav(page, 'Committee Queue')
  const row = page.getByRole('row').filter({ hasText: crNumber })
  await expect(row, 'routed request must be in the committee queue').toBeVisible()
  await row.getByRole('button', { name: 'Review' }).click()
  await expect(page.getByRole('button', { name: '← Back to queue' })).toBeVisible()
  return crNumber
}

test.describe('Epic 8 - Committee review & voting (UI)', () => {
  test('TC-UI-050 Routed assessment appears in the committee queue', async ({ page }) => {
    tc({ id: 'TC-UI-050', story: 'US-8.1', type: 'Functional', priority: 'P1', steps: ['Act as Jordan Blake (Committee)', 'Open Committee Queue'], expected: 'Queue row shows request #, type and title with a Review button' })
    const crNumber = state.need(K('crNumber'))
    await enterApp(page, USERS.committee1)
    await nav(page, 'Committee Queue')
    const row = page.getByRole('row').filter({ hasText: crNumber })
    await expect(row).toBeVisible()
    await snap(page, 'committee queue')
    actual(`queue row: ${(await row.textContent())?.replace(/\s+/g, ' ')}`)
  })

  test('TC-UI-051 Committee sees the full assessment before voting', async ({ page }) => {
    tc({ id: 'TC-UI-051', story: 'US-8.2', type: 'Functional', priority: 'P1', steps: ['Open Review on the queue item'], expected: 'Panel shows the narrative per category, residual scores, cited policy and the analyst override history, read-only' })
    defect('DEF-021')
    await openVotePanel(page, USERS.committee1)
    await snap(page, 'vote panel')
    const text = (await page.getByRole('main').textContent()) || ''
    const shows = { narrative: /Narrative|narrative/.test(text), scores: /Residual/.test(text), policy: /FFIEC|relied/i.test(text), overrides: /override/i.test(text) }
    actual(`vote panel contains only the title, vote form and vote list - narrative:${shows.narrative} scores:${shows.scores} policy:${shows.policy} overrides:${shows.overrides}`)
    expect.soft(shows.scores, 'scores visible to committee').toBe(true)
    expect.soft(shows.policy, 'cited policy visible to committee').toBe(true)
  })

  test('TC-UI-052 Vote validation: conditions / rationale mandatory', async ({ page }) => {
    tc({ id: 'TC-UI-052', story: 'US-8.2', type: 'Negative', priority: 'P1', steps: ['Choose ApproveWithConditions, leave conditions blank, Submit vote', 'Choose Reject, leave rationale blank, Submit', 'Choose Defer, leave rationale blank, Submit'], expected: 'Each blocked with the matching message; nothing recorded' })
    await openVotePanel(page, USERS.committee1)
    const main = page.getByRole('main')
    await choose(page, main.getByRole('combobox'), 'ApproveWithConditions')
    await expect(main.getByPlaceholder('Conditions')).toBeVisible()
    await main.getByRole('button', { name: 'Submit vote' }).click()
    await expect(toast(page, 'Conditions text is required for Approve-with-Conditions.')).toBeVisible()
    await snap(page, 'awc blank blocked')
    await choose(page, main.getByRole('combobox'), 'Reject')
    await main.getByRole('button', { name: 'Submit vote' }).click()
    await expect(toast(page, 'A rationale is required for Reject/Defer.')).toBeVisible()
    await choose(page, main.getByRole('combobox'), 'Defer')
    await main.getByRole('button', { name: 'Submit vote' }).click()
    await expect(toast(page, 'A rationale is required for Reject/Defer.').last()).toBeVisible()
    await snap(page, 'reject defer blank blocked')
    await expect(main.getByText('No votes yet.')).toBeVisible()
    actual('all three blank submissions blocked client-side; "No votes yet." still shown')
  })

  test('TC-UI-053 First member votes Approve-with-Conditions', async ({ page }) => {
    tc({ id: 'TC-UI-053', story: 'US-8.2', type: 'Functional', priority: 'P1', steps: ['As Jordan Blake choose ApproveWithConditions', 'Enter conditions', 'Submit vote'], expected: 'Toast "Vote cast"; vote list shows "Jordan Blake - ApproveWithConditions" with the conditions; no decision yet (quorum 2)' })
    await openVotePanel(page, USERS.committee1)
    const main = page.getByRole('main')
    await choose(page, main.getByRole('combobox'), 'ApproveWithConditions')
    await main.getByPlaceholder('Conditions').fill('Annual on-site audit of the vendor; cardholder PII encrypted at rest (QA)')
    await main.getByRole('button', { name: 'Submit vote' }).click()
    await expect(toast(page, 'Vote cast')).toBeVisible()
    const row = main.locator('.flex.items-center.justify-between').filter({ hasText: USERS.committee1 })
    await expect(row).toContainText('ApproveWithConditions')
    await snap(page, 'first vote cast')
    await expect(main.getByText(/^Resolved:/)).toHaveCount(0)
    actual(`vote row: ${(await row.textContent())?.replace(/\s+/g, ' ')}; no decision yet`)
  })

  test('TC-UI-054 Second vote reaches quorum and records the decision with conditions', async ({ page }) => {
    tc({ id: 'TC-UI-054', story: 'US-8.2 / US-8.3', type: 'E2E', priority: 'P1', steps: ['As Riley Voss open the item', 'Vote Approve'], expected: 'Decision banner "Resolved: ApprovedWithConditions" with the merged conditions; both votes listed individually' })
    await openVotePanel(page, USERS.committee2)
    const main = page.getByRole('main')
    await choose(page, main.getByRole('combobox'), 'Approve')
    await main.getByRole('button', { name: 'Submit vote' }).click()
    await expect(toast(page, 'Vote cast')).toBeVisible()
    const banner = main.getByText(/^Resolved:/)
    await expect(banner).toBeVisible()
    await snap(page, 'decision recorded')
    const votes = await main.locator('.flex.items-center.justify-between').allTextContents()
    actual(`${await banner.textContent()}; conditions "${await main.locator('.bg-emerald-50 p').nth(1).textContent()}"; votes: ${votes.map((v) => v.replace(/\s+/g, ' ')).join(' | ')}`)
    await expect(banner).toHaveText('Resolved: ApprovedWithConditions')
    expect(votes.length).toBe(2)
  })

  test('TC-UI-055 Decided item leaves the queue; Product Owner sees the outcome and conditions', async ({ page }) => {
    tc({ id: 'TC-UI-055', story: 'US-8.3 / US-1.3', type: 'Functional', priority: 'P1', steps: ['As Jordan Blake reload Committee Queue', 'As Priya Owens open My Requests'], expected: 'Item no longer queued; PO row shows the decision "Approved with Conditions" and the attached conditions' })
    defect('DEF-022')
    const crNumber = state.need(K('crNumber'))
    await enterApp(page, USERS.committee1)
    await nav(page, 'Committee Queue')
    await page.waitForTimeout(1000)
    const stillQueued = await page.getByRole('row').filter({ hasText: crNumber }).count()
    await snap(page, 'queue after decision')
    await enterApp(page, USERS.po)
    await nav(page, 'My Requests')
    const row = page.getByRole('row').filter({ hasText: crNumber })
    await expect(row).toBeVisible()
    await row.scrollIntoViewIfNeeded()
    await snap(page, 'po sees outcome')
    const cells = (await row.getByRole('cell').allTextContents()).map((s) => s.trim())
    actual(`still in queue: ${stillQueued > 0}; PO row status "${cells[3]}" - decision and conditions not shown to the requester`)
    expect(stillQueued).toBe(0)
    expect(cells[3]).toBe('Decisioned')
    expect.soft(cells.join(' '), 'PO should see the actual decision').toMatch(/Approved/)
  })
})
