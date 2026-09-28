import { defineConfig, devices } from '@playwright/test'

// Fixed once in the runner process so every worker (and a worker restarted after a failure)
// shares the same run id - lib/state.ts keys its on-disk lifecycle state by it.
process.env.RUN_ID ||= new Date().toISOString().replace(/[-:T]/g, '').slice(0, 12)

// Target: the deployed Azure Container Apps dev environment. Override with BASE_URL to point the
// same suite at a local stack (http://localhost:5210 serves API + built SPA from wwwroot).
export const BASE_URL =
  process.env.BASE_URL || 'https://ca-gh-hrg-workbench-dev.jollyplant-1cbb4459.eastus2.azurecontainerapps.io'

export default defineConfig({
  testDir: './specs',
  outputDir: './test-results',
  // The lifecycle specs are stateful (one change request walked intake -> decision), and the
  // environment is a shared dev DB, so run serially rather than racing ourselves.
  fullyParallel: false,
  workers: 1,
  retries: 0,
  timeout: 90_000,
  expect: { timeout: 15_000 },
  reporter: [
    ['list'],
    ['html', { outputFolder: 'playwright-report', open: 'never' }],
    ['json', { outputFile: 'results/results.json' }],
  ],
  use: {
    baseURL: BASE_URL,
    screenshot: 'on',
    trace: 'retain-on-failure',
    video: 'retain-on-failure',
    actionTimeout: 20_000,
    navigationTimeout: 45_000,
  },
  projects: [
    { name: 'api', testDir: './specs/api', use: { baseURL: BASE_URL } },
    { name: 'ui-desktop', testDir: './specs/ui', use: { ...devices['Desktop Chrome'], viewport: { width: 1440, height: 900 } } },
    { name: 'ui-mobile', testDir: './specs/responsive', use: { ...devices['Pixel 7'] } },
    { name: 'nfr', testDir: './specs/nfr', use: { ...devices['Desktop Chrome'], viewport: { width: 1440, height: 900 } } },
    // Read-only data tests against the database (DB_URL or .env.db); skipped when no URL is configured.
    { name: 'db', testDir: './specs/db' },
  ],
})
