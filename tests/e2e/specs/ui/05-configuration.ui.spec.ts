import { expect, test } from '@playwright/test'
import { actual, snap, tc } from '../../lib/harness'
import { card, choose, enterApp, nav, toast, USERS } from '../../lib/app'

// Same baseline as the API suite: positive saves write the observed live values back unchanged.
const BASELINE_MF = '0.85'

test.describe('Epic 10 - Configuration (Admin UI)', () => {
  test.beforeEach(async ({ page }) => {
    await enterApp(page, USERS.admin)
    await nav(page, 'Configuration')
    await expect(card(page, 'Workflow rules')).toBeVisible()
  })

  test('TC-UI-060 Workflow rules are listed in plain structured form', async ({ page }) => {
    tc({ id: 'TC-UI-060', story: 'US-10.2', type: 'Functional', priority: 'P2', steps: ['Open Configuration'], expected: 'Each rule shows its key and JSON value (e.g. CommitteeQuorum {"quorum": 2})' })
    const wr = card(page, 'Workflow rules')
    await expect(wr.getByText('CommitteeQuorum').first()).toBeVisible()
    await snap(page, 'configuration screen')
    actual(`rules shown: ${(await wr.locator('.rounded-md.border.p-3').allTextContents()).join(' | ')}`)
  })

  test('TC-UI-061 Workflow rule save requires a reason and valid JSON', async ({ page }) => {
    tc({ id: 'TC-UI-061', story: 'US-10.2', type: 'Negative', priority: 'P1', steps: ['Click Save rule with Reason blank', 'Enter a reason, set value to "{quorum: 2" and save', 'Restore value {"quorum": 2} and save with a reason'], expected: 'Blank reason blocked; invalid JSON blocked ("Rule value must be valid JSON."); valid save -> "Workflow rule updated"' })
    const wr = card(page, 'Workflow rules')
    await wr.getByRole('button', { name: 'Save rule' }).click()
    await expect(toast(page, /reason is required/)).toBeVisible()
    await snap(page, 'rule blocked no reason')
    const inputs = wr.getByRole('textbox')
    await inputs.nth(1).fill('QA: validation test')
    await inputs.nth(2).fill('{quorum: 2')
    await wr.getByRole('button', { name: 'Save rule' }).click()
    await expect(toast(page, 'Rule value must be valid JSON.')).toBeVisible()
    await snap(page, 'rule blocked invalid json')
    await inputs.nth(2).fill('{"quorum": 2}')
    await inputs.nth(1).fill('QA: re-save unchanged quorum')
    await wr.getByRole('button', { name: 'Save rule' }).click()
    await expect(toast(page, 'Workflow rule updated')).toBeVisible()
    await snap(page, 'rule saved')
    actual('blank reason blocked; invalid JSON blocked; unchanged value re-saved with reason')
  })

  test('TC-UI-062 Mitigation factor >= 1.0 is rejected; valid value saves', async ({ page }) => {
    tc({ id: 'TC-UI-062', story: 'US-10.1', type: 'Negative', priority: 'P1', steps: ['Scoring configuration: click Save with nothing filled', 'Pick Customers & Entities, factor 1.0, reason, Save', `Factor ${BASELINE_MF} (unchanged), reason, Save`], expected: 'Missing fields blocked; 1.0 rejected with the "residual risk reach zero" error; valid value -> "Scoring configuration updated"' })
    const sc = card(page, 'Scoring configuration')
    await sc.getByRole('button', { name: 'Save configuration' }).click()
    await expect(toast(page, 'Category, mitigation factor, and reason are all required.')).toBeVisible()
    await choose(page, sc.getByRole('combobox'), 'Customers & Entities')
    await sc.getByRole('spinbutton').fill('1.0')
    await sc.getByPlaceholder('Reason').fill('QA boundary test')
    await sc.getByRole('button', { name: 'Save configuration' }).click()
    const err = toast(page, /residual risk reach zero/)
    await expect(err).toBeVisible()
    await snap(page, 'mf 1.0 rejected')
    const msg = await err.textContent()
    await sc.getByRole('spinbutton').fill(BASELINE_MF)
    await sc.getByPlaceholder('Reason').fill('QA: re-save unchanged baseline')
    await sc.getByRole('button', { name: 'Save configuration' }).click()
    await expect(toast(page, 'Scoring configuration updated')).toBeVisible()
    await snap(page, 'mf saved')
    actual(`1.0 rejected: "${msg}"; ${BASELINE_MF} saved`)
  })
})
