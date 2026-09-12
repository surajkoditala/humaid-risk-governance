import { expect, test } from '@playwright/test';
import { NON_EXISTENT_ID, usersByRole } from '../fixtures/users.js';

/**
 * Access control on the Workbench API.
 *
 * Every test here asserts the SECURE expectation, and the ones that currently cannot pass are
 * annotated `test.fail()`. That is deliberate: the suite stays green while the gap is open, and
 * the moment somebody implements role checks Playwright reports "expected to fail, but passed" -
 * so the fix announces itself instead of being discovered months later. Delete the annotation (not
 * the test) when that happens.
 *
 * ---------------------------------------------------------------------------------------------
 * THE UNDERLYING FINDING
 *
 * Two separate problems compound here.
 *
 * 1. There is no caller identity. Every controller carries a bare [Authorize], and in Development
 *    with AUTH0_DOMAIN blank, DevBypassAuthHandler authenticates EVERY request - no header needed
 *    - as a single generic "system-dev" principal. So [Authorize] currently proves nothing.
 *
 * 2. The acting user is self-declared. Every write endpoint reads the actor from the REQUEST BODY
 *    (CastCommitteeVoteInput.CommitteeMemberUserId, FinalizeBody.ActorUserId,
 *    UpsertScoringConfigInput.ActorUserId) rather than from the token - DevBypassAuthHandler's own
 *    summary says so explicitly. No endpoint checks that the declared actor holds the role the
 *    action requires.
 *
 * Together: any caller can perform any action as any user. That directly undermines US-8.2 AC5
 * (each committee member's vote individually and accountably recorded), US-6.3 AC3 (the
 * finalizing analyst's identity "cannot be anonymous or attributed to 'system'"), and US-10.1
 * (scoring configuration is for analysts "with configuration privileges").
 *
 * Note this is a Development-mode posture. It is not a live breach - no Auth0 tenant exists yet
 * and the data is synthetic - but the authorization layer it stands in for has not been written,
 * so configuring Auth0 alone would not close it.
 * ---------------------------------------------------------------------------------------------
 */

test.describe('Authentication', () => {
  test('the user directory is not readable without a credential', async ({ request }) => {
    test.fail(); // DevBypassAuthHandler authenticates every request; returns 200 + all six users.

    const response = await request.get('/api/User');
    test.info().annotations.push({ type: 'actual status', description: String(response.status()) });

    // Returns every user's display name, email and role to an unauthenticated caller.
    expect(response.status(), 'unauthenticated read of /api/User should be rejected').toBe(401);
  });

  test('Ping stays deliberately open', async ({ request }) => {
    // The counter-example, and a genuine assertion rather than a known-gap marker: PingController
    // carries no [Authorize] ON PURPOSE (see its own summary) so the webapp can health-check
    // before Auth0 exists. Pinned so that "everything is open" and "this one is open by design"
    // stay distinguishable.
    const response = await request.get('/api/Ping');

    expect(response.status()).toBe(200);
    expect((await response.json()).data).toBe('pong');
  });
});

test.describe('Role enforcement', () => {
  test('a Product Owner cannot be recorded as a committee voter', async ({ request }) => {
    test.fail(); // No role check exists on this endpoint.

    const { productOwner } = await usersByRole(request);
    expect(productOwner, 'seeded ProductOwner not found').toBeTruthy();

    const response = await request.post('/api/Committee/Vote', {
      data: {
        assessmentId: NON_EXISTENT_ID,
        committeeMemberUserId: productOwner.id,
        vote: 'Approve',
      },
    });
    test.info().annotations.push({ type: 'actual status', description: String(response.status()) });

    // 403 specifically: a role violation must be refused on authorization grounds, BEFORE the
    // assessment is even looked up. A 400 "not routed to committee" would mean the request was
    // rejected for workflow reasons and the role was never considered at all - which is exactly
    // the confusion this assertion is designed not to accept.
    expect(response.status(), 'US-8.2 AC5: only a CommitteeMember may cast a vote').toBe(403);
  });

  test('a Product Owner cannot finalize an assessment', async ({ request }) => {
    test.fail(); // No role check exists on this endpoint.

    const { productOwner } = await usersByRole(request);
    const response = await request.post(`/api/Assessment/${NON_EXISTENT_ID}/Finalize`, {
      data: { actorUserId: productOwner.id },
    });
    test.info().annotations.push({ type: 'actual status', description: String(response.status()) });

    expect(response.status(), 'US-6.3: finalization is the FCRM Analyst’s act').toBe(403);
  });

  test('a Product Owner cannot change scoring configuration', async ({ request }) => {
    test.fail(); // No role check exists on this endpoint.

    const { productOwner } = await usersByRole(request);
    const response = await request.post('/api/Scoring/Config', {
      data: {
        riskCategoryId: NON_EXISTENT_ID,
        maxMitigationFactor: 0.5,
        reason: 'Authorization probe - should never be applied.',
        actorUserId: productOwner.id,
      },
    });
    test.info().annotations.push({ type: 'actual status', description: String(response.status()) });

    expect(
      response.status(),
      'US-10.1: scoring configuration requires configuration privileges',
    ).toBe(403);
  });
});

test.describe('Input validation still holds', () => {
  // These pass today. They matter because they show the API is not simply accepting everything -
  // the gap above is specifically an AUTHORIZATION gap, not an absence of validation. Keeping
  // both kinds of evidence in one file stops the finding being overstated.

  test('a scoring config that would zero out residual risk is rejected', async ({ request }) => {
    const { analyst } = await usersByRole(request);

    const response = await request.post('/api/Scoring/Config', {
      data: {
        riskCategoryId: NON_EXISTENT_ID,
        maxMitigationFactor: 1.0, // US-10.1 AC2 - controls mitigate, never eliminate.
        reason: 'Probe: a mitigation factor of 1.0 must be refused.',
        actorUserId: analyst?.id ?? NON_EXISTENT_ID,
      },
    });

    expect(response.status(), 'a mitigation factor of 1.0 must never be accepted').not.toBe(200);
  });

  test('a malformed GUID is rejected by routing, not passed through', async ({ request }) => {
    const response = await request.get('/api/Assessment/not-a-guid/Readiness');

    expect(response.status()).toBe(404);
  });
});
