import { expect, test, type Page } from '@playwright/test'
import { actual, snap, tc } from '../../lib/harness'
import { enterApp, USERS } from '../../lib/app'

async function overflowX(page: Page) {
  return page.evaluate(() => {
    const el = document.scrollingElement!
    return { scrollWidth: el.scrollWidth, clientWidth: el.clientWidth }
  })
}

async function openMenu(page: Page) {
  await page.getByRole('banner').getByRole('button').first().click()
  await expect(page.getByRole('navigation')).toBeInViewport()
}

const SCREENS: [string, string, string][] = [
  ['TC-RWD-002', USERS.po, 'Submit Request'],
  ['TC-RWD-003', USERS.po, 'My Requests'],
  ['TC-RWD-004', USERS.analyst, 'Assessments'],
  ['TC-RWD-005', USERS.committee1, 'Committee Queue'],
  ['TC-RWD-006', USERS.admin, 'Configuration'],
]

test.describe('Responsive layout (Pixel 7, 412 px)', () => {
  test('TC-RWD-001 Sidebar collapses behind a menu button on mobile', async ({ page }) => {
    tc({ id: 'TC-RWD-001', story: 'NFR-UX', type: 'Responsive', priority: 'P2', steps: ['Open the app on a Pixel 7 viewport as Priya Owens', 'Check the sidebar is off-canvas', 'Tap the menu button', 'Tap "My Requests"'], expected: 'Sidebar hidden by default, slides in on menu tap, closes after navigating' })
    await enterApp(page, USERS.po)
    await expect(page.getByRole('navigation')).not.toBeInViewport()
    await snap(page, 'mobile default')
    await openMenu(page)
    await snap(page, 'mobile menu open')
    await page.getByRole('navigation').getByRole('button', { name: 'My Requests' }).click()
    await expect(page.getByRole('navigation')).not.toBeInViewport()
    await expect(page.getByText('My requests', { exact: true })).toBeVisible()
    await snap(page, 'mobile after navigate')
    actual('sidebar off-canvas by default; opens on menu tap; closes after choosing a screen')
  })

  for (const [id, user, screen] of SCREENS) {
    test(`${id} "${screen}" fits a 412 px viewport without horizontal scrolling`, async ({ page }) => {
      tc({ id, story: 'NFR-UX', type: 'Responsive', priority: 'P3', steps: [`As ${user} open ${screen} on Pixel 7`, 'Measure document scroll width vs viewport'], expected: 'scrollWidth <= clientWidth (no page-level horizontal scroll); content readable' })
      await enterApp(page, user)
      await openMenu(page)
      await page.getByRole('navigation').getByRole('button', { name: screen }).click()
      await page.waitForTimeout(1200)
      const m = await overflowX(page)
      await snap(page, `${screen} mobile`)
      actual(`scrollWidth ${m.scrollWidth} px vs viewport ${m.clientWidth} px`)
      expect(m.scrollWidth).toBeLessThanOrEqual(m.clientWidth + 1)
    })
  }

  test('TC-RWD-007 Assessment workspace tabs are reachable on mobile', async ({ page }) => {
    tc({ id: 'TC-RWD-007', story: 'NFR-UX', type: 'Responsive', priority: 'P3', steps: ['As Amara Chen open the first request in Assessments', 'Scroll the tab strip to "Audit" and open it'], expected: 'Tab strip scrolls horizontally inside its container; page itself does not overflow; Audit tab opens' })
    await enterApp(page, USERS.analyst)
    await page.getByRole('button', { name: 'Open' }).first().click()
    const audit = page.getByRole('tab', { name: 'Audit' })
    await audit.scrollIntoViewIfNeeded()
    await audit.click()
    await expect(audit).toHaveAttribute('aria-selected', 'true')
    const m = await overflowX(page)
    await snap(page, 'workspace audit tab mobile')
    actual(`Audit tab opened; page scrollWidth ${m.scrollWidth} vs ${m.clientWidth}`)
    expect(m.scrollWidth).toBeLessThanOrEqual(m.clientWidth + 1)
  })
})
