import { expect } from '@playwright/test';

export const WEBAPP_BASE_URL = process.env.WEBAPP_BASE_URL ?? 'http://localhost:3000';
export const API_BASE_URL = process.env.API_BASE_URL ?? 'http://localhost:5210';

/** Auth0 is not configured in local dev, so the app opens on a bypass gate first. */
const BYPASS = /Continue without signing in/i;

let cachedUsers = null;

export async function seededUsers() {
  if (!cachedUsers) {
    const response = await fetch(`${API_BASE_URL}/api/User`);
    if (!response.ok) throw new Error(`GET /api/User returned ${response.status} - is the API seeded?`);
    cachedUsers = (await response.json()).data ?? [];
  }
  return cachedUsers;
}

export async function userWithRole(role) {
  const user = (await seededUsers()).find((u) => u.role === role);
  if (!user) throw new Error(`No seeded user with role ${role} - check seed_dev_users.sql.`);
  return user;
}

/**
 * Opens the app as one of the seeded users.
 *
 * There is no login to automate: DevUserContext.jsx reads the acting user straight out of
 * localStorage (`devUserId`) while Auth0 is unconfigured, so seeding that key before the first
 * paint IS the sign-in. Faster and far less brittle than driving a user-picker, and it is the
 * same mechanism the app itself uses rather than a test-only backdoor.
 */
export async function openAppAs(browser, role) {
  const user = await userWithRole(role);
  const context = await browser.newContext({ viewport: { width: 1440, height: 1100 } });
  await context.addInitScript((id) => window.localStorage.setItem('devUserId', id), user.id);

  const page = await context.newPage();
  await page.goto(WEBAPP_BASE_URL, { waitUntil: 'domcontentloaded' });

  const bypass = page.getByRole('button', { name: BYPASS });
  if (await bypass.count()) await bypass.click();

  // Proves the role actually took effect before any assertion depends on it.
  await expect(page.getByText(`${user.displayName} — ${role}`)).toBeVisible();
  return { context, page, user };
}

/**
 * Nav items and form submit buttons collide by accessible name - the sidebar has "Submit Request"
 * while the intake form has "Submit request". Playwright's name matching is case-insensitive
 * unless `exact` is set, so without this every nav click is a strict-mode violation.
 */
export function nav(page, label) {
  return page.getByRole('button', { name: label, exact: true });
}

export const TABS = ['Categories', 'Policy', 'Extraction', 'Narrative', 'Scoring', 'Finalize', 'Audit'];

export function tab(page, name) {
  return page.getByRole('tab', { name });
}

/**
 * Creates a change request straight through the API, for tests whose subject is a later stage.
 * Returns the created record - `{ id, requestNumber, title, status, ... }`.
 */
export async function createChangeRequest(title = 'Onboard a third-party KYC verification vendor') {
  const submitter = await userWithRole('ProductOwner');
  const response = await fetch(`${API_BASE_URL}/api/ChangeRequest/Submit`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      changeType: 'Vendor',
      title,
      description:
        'Engage an external vendor to perform identity verification checks on new customers, ' +
        'requiring the vendor to receive customer PII including government ID scans.',
      typeSpecificFields: { vendor_name: 'SettleCorr Ltd', jurisdiction: 'SG' },
      submittedByUserId: submitter.id,
    }),
  });
  if (!response.ok) throw new Error(`Submit returned ${response.status}: ${await response.text()}`);
  return (await response.json()).data;
}
