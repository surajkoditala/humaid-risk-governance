import { expect, test } from '@playwright/test';
import { WEBAPP_BASE_URL, nav, openAppAs, tab } from '../fixtures/app.js';

/**
 * The three role journeys, run in order as one continuous story: a Product Owner raises a change,
 * an FCRM Analyst assesses and finalizes it, the Risk Committee votes. This is the golden path the
 * product exists to deliver, and the sequence an examiner would reconstruct from the audit trail.
 *
 * Deliberately serial and deliberately small. These three carry the whole governance chain; a
 * broader UI suite would mostly re-prove what the 62 unit tests already cover at a fraction of the
 * cost. Three journeys, not thirty.
 *
 * Requires the full stack: Postgres + Azurite, Mock Systems (:5220), the API (:5210) and the Vite
 * dev server (:3000). See ../README.md.
 */
test.describe.configure({ mode: 'serial' });

// Carried between the three journeys - this is one request moving through the workflow, not three
// unrelated fixtures.
const change = {
  title: `Launch same-day international wire transfer service ${Date.now()}`,
  requestNumber: null,
};

test.beforeAll(async () => {
  // globalSetup guards the API; the webapp is this project's own extra dependency, so it is
  // checked here rather than forcing every API-only run to also need Vite.
  try {
    const response = await fetch(WEBAPP_BASE_URL);
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
  } catch (error) {
    throw new Error(
      `Cannot reach the webapp at ${WEBAPP_BASE_URL} (${error.message}).\n` +
        `Start it with:  cd webapp && npm run dev`,
    );
  }
});

test('journey 1 — a Product Owner raises a change request', async ({ browser }) => {
  const { context, page } = await openAppAs(browser, 'ProductOwner');

  await nav(page, 'Submit Request').click();

  // The intake form is the first form on the page; the second is the attach-document form, and
  // the header carries a third combobox (the dev user switcher) - so scope to the form.
  const form = page.locator('form').first();
  await form.getByRole('combobox').first().click();
  await page.getByRole('option', { name: 'Product', exact: true }).click();

  await page.locator('#title').fill(change.title);
  await page.locator('#description').fill(
    'New product allowing retail and commercial customers to send same-day international wire ' +
      'transfers to over 40 countries, including several FATF-monitored jurisdictions, via ' +
      'online and branch channels.',
  );
  await page.locator('#details').fill('{"channels":["online","branch"],"daily_limit_usd":500000}');
  await form.getByRole('button', { name: 'Submit request', exact: true }).click();

  // US-1.1 AC4 - a unique, immutable request id is assigned on submission.
  const confirmation = page.getByText(/Submitted as CR-\d{4}-\d{5}/);
  await expect(confirmation).toBeVisible();
  change.requestNumber = (await confirmation.innerText()).match(/CR-\d{4}-\d{5}/)[0];

  // US-1.3 - the requester can see status without emailing FCRM.
  await nav(page, 'My Requests').click();
  const row = page.locator('table tbody tr').filter({ hasText: change.requestNumber });
  await expect(row).toBeVisible();
  await expect(row).toContainText('Product');
  await expect(row).toContainText('Submitted');

  await context.close();
});

test('journey 2 — an FCRM Analyst assesses and finalizes it', async ({ browser }) => {
  expect(change.requestNumber, 'journey 1 must have produced a request number').toBeTruthy();
  const { context, page } = await openAppAs(browser, 'Analyst');

  await nav(page, 'Assessments').click();
  const row = page.locator('table tbody tr').filter({ hasText: change.requestNumber });
  await expect(row, 'US-1.1 - a submitted request reaches the analyst inbox').toBeVisible();

  // DEF-006: the first Open always errors (see governance.spec.js). Retrying is how an analyst
  // gets in today, so the journey does what they do - and the defect is asserted separately
  // rather than silently absorbed here.
  await row.getByRole('button', { name: 'Open', exact: true }).click();
  await page.waitForTimeout(1500);
  if (await page.getByRole('tab', { name: 'Categories' }).count() === 0) {
    await nav(page, 'Assessments').click();
    await row.getByRole('button', { name: 'Open', exact: true }).click();
  }

  await expect(page.getByText(change.title)).toBeVisible();

  // All seven stages of the workspace are reachable (Epics 2-9 in one screen).
  for (const name of ['Categories', 'Policy', 'Extraction', 'Narrative', 'Scoring', 'Finalize', 'Audit']) {
    await expect(tab(page, name)).toBeVisible();
  }

  // US-9.1 - intake is already on the audit trail, attributed to a named human, before the
  // analyst has done anything at all.
  await tab(page, 'Audit').click();
  await expect(page.getByText(/ChangeRequest\.Created by Priya Owens/)).toBeVisible();

  await tab(page, 'Finalize').click();
  await page.getByRole('button', { name: 'Finalize', exact: true }).click();
  await expect(page.getByText('Finalized').first()).toBeVisible();

  await page.getByRole('button', { name: 'Route to committee', exact: true }).click();
  await page.waitForTimeout(1200);

  await context.close();
});

test('journey 3 — the Risk Committee reviews and votes', async ({ browser }) => {
  expect(change.requestNumber, 'journey 1 must have produced a request number').toBeTruthy();
  const { context, page, user } = await openAppAs(browser, 'CommitteeMember');

  await nav(page, 'Committee Queue').click();

  // US-8.1 - a finalized assessment appears in the committee's queue.
  const row = page.locator('table tbody tr').filter({ hasText: change.requestNumber });
  await expect(row).toBeVisible();
  await row.getByRole('button', { name: /Review|Open/i }).click();

  await expect(page.getByText(change.title)).toBeVisible();
  await expect(page.getByText(/every member's vote is recorded individually/i)).toBeVisible();

  const voteCombo = page.getByRole('combobox').filter({ hasNotText: user.displayName }).first();
  await voteCombo.click();
  await page.getByRole('option', { name: 'Approve', exact: true }).click();
  await page.getByRole('button', { name: 'Submit vote', exact: true }).click();

  // US-8.2 AC5 - the vote is recorded against this member by name, never anonymised or
  // aggregated away.
  await expect(page.getByText(user.displayName).first()).toBeVisible();
  await expect(page.getByText('No votes yet.')).toBeHidden();

  await context.close();
});
