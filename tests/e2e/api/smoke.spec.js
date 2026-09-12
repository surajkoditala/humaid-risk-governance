import { expect, test } from '@playwright/test';
import { usersByRole } from '../fixtures/users.js';

/**
 * Proves the harness itself works and pins the API's response contract. If these fail, the
 * problem is the stack or the wiring - not the thing any other spec is trying to measure.
 */
test.describe('API smoke', () => {
  test('every response uses the OperationResult envelope', async ({ request }) => {
    // BaseApiController.ExecuteAsync wraps every action, so `data` (not a bare body) is the
    // contract the webapp and these tests both rely on.
    const response = await request.get('/api/Ping');

    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body).toHaveProperty('isSuccessful', true);
    expect(body).toHaveProperty('data');
  });

  test('the seeded users cover all four roles', async ({ request }) => {
    // seed_dev_users.sql seeds six users across four roles. Every role journey in the UI suite
    // will depend on these, so a broken or partial seed should be caught here first.
    const { productOwner, analyst, committeeMember, admin, all } = await usersByRole(request);

    expect(all.length).toBeGreaterThanOrEqual(6);
    expect(productOwner, 'ProductOwner').toBeTruthy();
    expect(analyst, 'Analyst').toBeTruthy();
    expect(committeeMember, 'CommitteeMember').toBeTruthy();
    expect(admin, 'Admin').toBeTruthy();
  });

  test('the FFIEC risk framework is seeded with its four categories', async ({ request }) => {
    // CLAUDE.md: risk decomposition must be grounded in a real, citable framework and the four
    // FFIEC categories are fixed. An empty or partial list here would silently weaken every
    // category-mapping result downstream.
    const response = await request.get('/api/CategoryMapping/Categories');
    expect(response.status()).toBe(200);

    const categories = (await response.json()).data ?? [];
    const codes = categories.map((c) => c.code ?? c.Code);

    expect(codes).toEqual(
      expect.arrayContaining([
        'PRODUCTS_SERVICES',
        'CUSTOMERS_ENTITIES',
        'GEOGRAPHIC_LOCATIONS',
        'DELIVERY_CHANNELS',
      ]),
    );
  });
});
