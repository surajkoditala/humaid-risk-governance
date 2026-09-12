import { defineConfig } from '@playwright/test';

// The Workbench API (1-API) and, later, the Vite webapp (5-Presentation). Both default to the
// ports ops/README.md and the root README document; override per environment rather than editing
// this file.
const API_BASE_URL = process.env.API_BASE_URL ?? 'http://localhost:5210';

export default defineConfig({
  testDir: './',
  fullyParallel: true,

  // A .only left in a spec silently narrows the suite - fine locally, never acceptable in CI.
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,

  reporter: [['list'], ['html', { open: 'never' }]],

  // Fails the whole run with a readable message if the API is not up. Without this, every
  // test.fail()-annotated test in api/authorization.spec.js would "pass" against a dead server -
  // a connection refusal is not the same claim as "the endpoint rejected me", and a suite that
  // conflates the two is worse than no suite.
  globalSetup: './global-setup.js',

  projects: [
    {
      name: 'api',
      testDir: './api',
      use: {
        baseURL: API_BASE_URL,
        extraHTTPHeaders: { Accept: 'application/json' },
      },
    },

    // A 'ui' project (three role journeys: Product Owner submits -> Analyst assesses and
    // finalizes -> Committee votes) is the next step. Deliberately not scaffolded empty: it needs
    // the Vite dev server and both .NET services running, which is a heavier orchestration story
    // than the API project above. See README.md.
  ],
});
