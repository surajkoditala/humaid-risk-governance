import { expect, type APIRequestContext, type Locator, type Page } from '@playwright/test'

// Seeded synthetic users on the dev environment (see GET /api/User).
export const USERS = {
  admin: 'Taylor Finch',
  analyst: 'Amara Chen',
  analyst2: 'Sam Okafor',
  committee1: 'Jordan Blake',
  committee2: 'Riley Voss',
  po: 'Priya Owens',
} as const

export type AppUser = { id: string; displayName: string; role: string; email: string }

let cachedUsers: AppUser[] | null = null
export async function users(request: APIRequestContext): Promise<AppUser[]> {
  if (!cachedUsers) {
    const res = await request.get('/api/User')
    cachedUsers = (await res.json()).data
  }
  return cachedUsers!
}
export async function userId(request: APIRequestContext, displayName: string) {
  const u = (await users(request)).find((x) => x.displayName === displayName)
  if (!u) throw new Error(`Seed user ${displayName} not found`)
  return u.id
}

/** Loads the SPA, takes the (dev-only) "continue without signing in" gate, and acts as `displayName`. */
export async function enterApp(page: Page, displayName?: string) {
  await page.goto('/')
  await page.getByRole('button', { name: /Continue without signing in/ }).click()
  await expect(page.getByRole('banner').getByRole('combobox')).toBeVisible()
  if (displayName) await actAs(page, displayName)
}

export async function actAs(page: Page, displayName: string) {
  const switcher = page.getByRole('banner').getByRole('combobox')
  await expect(switcher).not.toHaveText(/Loading users/)
  if ((await switcher.textContent())?.startsWith(displayName)) return
  await switcher.click()
  await page.getByRole('option', { name: new RegExp(`^${displayName} —`) }).click()
  await expect(switcher).toContainText(displayName)
}

export async function nav(page: Page, label: string) {
  await page.getByRole('navigation').getByRole('button', { name: label }).click()
}

/** base-ui Select: click the trigger, pick the option by accessible name. */
export async function choose(page: Page, trigger: Locator, option: string | RegExp) {
  await trigger.click()
  await page.getByRole('option', { name: option }).first().click()
}

export function toast(page: Page, text: string | RegExp) {
  return page.locator('[data-sonner-toast]').filter({ hasText: text }).first()
}

export function card(page: Page, title: string | RegExp) {
  return page.locator('[data-slot="card"]').filter({ has: page.locator('[data-slot="card-title"]', { hasText: title }) }).first()
}

/** Captures console errors + failed network calls so each screen can assert it's clean. */
export function watchPage(page: Page) {
  const consoleErrors: string[] = []
  const failedRequests: string[] = []
  page.on('console', (m) => m.type() === 'error' && consoleErrors.push(m.text()))
  page.on('pageerror', (e) => consoleErrors.push(`pageerror: ${e.message}`))
  page.on('response', (r) => r.status() >= 500 && failedRequests.push(`${r.status()} ${r.request().method()} ${r.url()}`))
  return { consoleErrors, failedRequests }
}
