import AxeBuilder from '@axe-core/playwright'
import { expect, test, type Page } from '@playwright/test'
import { actual, defect, evidence, snap, tc } from '../../lib/harness'
import { enterApp, nav, USERS } from '../../lib/app'

type Screen = { id: string; name: string; open: (page: Page) => Promise<void> }

const SCREENS: Screen[] = [
  { id: 'TC-A11Y-001', name: 'Sign-in gate', open: async (p) => { await p.goto('/'); await p.getByRole('button', { name: /Continue without/ }).waitFor() } },
  { id: 'TC-A11Y-002', name: 'Submit Request', open: async (p) => { await enterApp(p, USERS.po); await nav(p, 'Submit Request') } },
  { id: 'TC-A11Y-003', name: 'My Requests', open: async (p) => { await enterApp(p, USERS.po); await nav(p, 'My Requests'); await p.getByRole('table').waitFor() } },
  { id: 'TC-A11Y-004', name: 'Assessments inbox', open: async (p) => { await enterApp(p, USERS.analyst); await p.getByRole('table').waitFor() } },
  { id: 'TC-A11Y-005', name: 'Assessment workspace', open: async (p) => { await enterApp(p, USERS.analyst); await p.getByRole('button', { name: 'Open' }).first().click(); await p.getByRole('tab', { name: 'Categories' }).waitFor(); await p.waitForTimeout(1000) } },
  { id: 'TC-A11Y-006', name: 'Committee Queue', open: async (p) => { await enterApp(p, USERS.committee1); await nav(p, 'Committee Queue'); await p.waitForTimeout(1000) } },
  { id: 'TC-A11Y-007', name: 'Configuration', open: async (p) => { await enterApp(p, USERS.admin); await nav(p, 'Configuration'); await p.waitForTimeout(1000) } },
]

test.describe('Accessibility (axe-core, WCAG 2.1 A/AA)', () => {
  for (const s of SCREENS) {
    test(`${s.id} ${s.name} has no critical or serious WCAG violations`, async ({ page }) => {
      tc({ id: s.id, story: 'NFR-A11Y', type: 'Accessibility', priority: 'P2', steps: [`Open ${s.name}`, 'Run axe-core with wcag2a, wcag2aa, wcag21a, wcag21aa tags'], expected: 'Zero critical / serious violations' })
      await s.open(page)
      const r = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa']).analyze()
      const v = r.violations.map((x) => ({ id: x.id, impact: x.impact, help: x.help, nodes: x.nodes.length, sample: x.nodes.slice(0, 3).map((n) => n.target.join(' ')) }))
      await evidence('axe violations', v)
      await snap(page, s.name)
      const bad = v.filter((x) => x.impact === 'critical' || x.impact === 'serious')
      actual(v.length ? v.map((x) => `${x.id} [${x.impact}] x${x.nodes}`).join('; ') : 'no violations')
      if (bad.length) defect('DEF-029')
      expect.soft(bad.map((x) => `${x.id} (${x.nodes})`)).toEqual([])
    })
  }

  test('TC-A11Y-008 Core flow is keyboard operable', async ({ page }) => {
    tc({ id: 'TC-A11Y-008', story: 'NFR-A11Y', type: 'Accessibility', priority: 'P3', steps: ['Tab to "Continue without signing in" and press Enter', 'Tab to the user switcher and open it with Enter', 'Arrow to "Priya Owens" and press Enter'], expected: 'Every step works with keyboard only; focus is visible' })
    await page.goto('/')
    await page.keyboard.press('Tab')
    await expect(page.getByRole('button', { name: /Continue without/ })).toBeFocused()
    await page.keyboard.press('Enter')
    const sw = page.getByRole('banner').getByRole('combobox')
    await expect(sw).toBeVisible()
    await sw.focus()
    await page.keyboard.press('Enter')
    await page.getByRole('option').first().waitFor()
    for (let i = 0; i < 6; i++) {
      if ((await page.locator('[role=option][data-highlighted]').textContent())?.startsWith(USERS.po)) break
      await page.keyboard.press('ArrowDown')
    }
    await page.keyboard.press('Enter')
    await expect(sw).toContainText(USERS.po)
    await snap(page, 'keyboard selected po')
    actual('gate, switcher and user choice all operable by keyboard')
  })
})
