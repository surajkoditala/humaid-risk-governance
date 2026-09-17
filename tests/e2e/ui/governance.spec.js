import { expect, test } from '@playwright/test';
import { API_BASE_URL, createChangeRequest, nav, openAppAs, tab } from '../fixtures/app.js';

/**
 * Governance defects proven through the UI, the way an analyst would actually hit them.
 *
 * Both assert the CORRECT behaviour and are annotated test.fail(), so the board stays green while
 * the gap is open and Playwright reports "expected to fail, but passed" the moment either is
 * fixed. Delete the annotation, not the test.
 */

test.describe('DEF-004 — an empty assessment must not reach the committee', () => {
  /**
   * The single most serious finding in the product so far.
   *
   * CLAUDE.md: "the system prepares, humans decide... don't let an AI output reach the committee
   * stage without a corresponding review gate in code." AssessmentService.CheckReadinessAsync
   * iterates over the ACTIVE MAPPED CATEGORIES; with none mapped, both loops are no-ops and
   * IsReady is vacuously true. The Finalize tab then cheerfully reports "Ready to finalize."
   *
   * Verified end to end on 2026-09-12: a request with zero categories, zero policy reliance
   * decisions, zero extracted fields, zero narrative and zero risk scores was finalized, routed,
   * and appeared in the committee queue with a live "Submit vote" button. The committee is being
   * asked to take an accountable decision on a document containing nothing but a title.
   */
  test('the Finalize tab refuses an assessment with nothing reviewed', async ({ browser }) => {
    test.fail(); // Currently reports "Ready to finalize." - see DEF-004.

    const change = await createChangeRequest(`Empty-assessment probe ${Date.now()}`);
    const { context, page } = await openAppAs(browser, 'Analyst');

    await nav(page, 'Assessments').click();
    const row = page.locator('table tbody tr').filter({ hasText: change.requestNumber });
    await row.getByRole('button', { name: 'Open', exact: true }).click();
    await page.waitForTimeout(1500);
    if ((await tab(page, 'Categories').count()) === 0) {
      await nav(page, 'Assessments').click();
      await row.getByRole('button', { name: 'Open', exact: true }).click();
    }

    // Nothing has been mapped, researched, extracted, drafted or scored at this point.
    await tab(page, 'Categories').click();
    await expect(page.getByText('No categories mapped yet.')).toBeVisible();

    await tab(page, 'Finalize').click();
    await expect(
      page.getByText(/Ready to finalize/i),
      'an assessment with no mapped categories is not ready for a committee decision',
    ).toBeHidden();

    await context.close();
  });

  test('an unreviewed assessment cannot be routed to the committee queue', async ({ browser }) => {
    test.fail(); // It routes, and the committee can vote on it.

    const change = await createChangeRequest(`Routing probe ${Date.now()}`);

    const analyst = await openAppAs(browser, 'Analyst');
    await nav(analyst.page, 'Assessments').click();
    const row = analyst.page.locator('table tbody tr').filter({ hasText: change.requestNumber });
    await row.getByRole('button', { name: 'Open', exact: true }).click();
    await analyst.page.waitForTimeout(1500);
    if ((await tab(analyst.page, 'Finalize').count()) === 0) {
      await nav(analyst.page, 'Assessments').click();
      await row.getByRole('button', { name: 'Open', exact: true }).click();
    }
    await tab(analyst.page, 'Finalize').click();
    await analyst.page.getByRole('button', { name: 'Finalize', exact: true }).click();
    await analyst.page.getByRole('button', { name: 'Route to committee', exact: true }).click();
    await analyst.page.waitForTimeout(1200);
    await analyst.context.close();

    const committee = await openAppAs(browser, 'CommitteeMember');
    await nav(committee.page, 'Committee Queue').click();

    await expect(
      committee.page.locator('table tbody tr').filter({ hasText: change.requestNumber }),
      'an assessment with no narrative, policy or score must never reach a committee vote',
    ).toBeHidden();

    await committee.context.close();
  });
});

test.describe('DEF-006 — opening an assessment workspace', () => {
  /**
   * func_getOrCreateAssessment does SELECT-then-INSERT with no ON CONFLICT and no lock:
   *
   *   SELECT id INTO v_id FROM assessment WHERE change_request_id = p_change_request_id;
   *   IF v_id IS NULL THEN INSERT INTO assessment ...
   *
   * React 18 StrictMode double-invokes effects in dev, so two POSTs race. Both read NULL, both
   * insert, and the loser violates UNIQUE (change_request_id) -> Npgsql 23505 -> HTTP 500.
   *
   * The row IS created, so a second click works. Net effect for an analyst: opening a workspace
   * fails the first time, every time. The fix is ON CONFLICT DO NOTHING plus a re-select, which
   * also makes the function safe for two analysts opening the same request at once - a race that
   * survives regardless of what StrictMode does in production.
   */
  /**
   * NOTE ON WHAT IS *NOT* TESTED HERE.
   *
   * A browser-level version of this - click Open, assert no 500 - was written first and removed,
   * because it is inherently flaky: it only fails when the two StrictMode requests genuinely
   * overlap, and it passed on one full-suite run while failing in isolation. A test.fail() marker
   * that oscillates is worse than no test, because it trains everyone to ignore the signal.
   *
   * The deterministic version below drives the race directly with Promise.all. It reproduces the
   * same 23505 every time, and it makes the stronger claim anyway: this is a stored-function
   * defect, not a React dev-mode artefact. Two analysts opening the same request at the same
   * moment would hit it in production, where StrictMode does not apply.
   */
  test('two concurrent opens of the same request both succeed', async () => {
    test.fail(); // One of the pair returns 500 (Npgsql 23505 on assessment_change_request_id_key).

    const change = await createChangeRequest(`Concurrent open probe ${Date.now()}`);

    const open = () =>
      fetch(`${API_BASE_URL}/api/Assessment/OpenWorkspace/${change.id}`, { method: 'POST' });
    const [first, second] = await Promise.all([open(), open()]);

    expect(
      [first.status, second.status],
      'func_getOrCreateAssessment must be idempotent under concurrent callers',
    ).toEqual([200, 200]);
  });
});
