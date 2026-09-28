# End-to-end test suite (Playwright)

Functional UI, REST API and non-functional (security, performance, accessibility, responsive) tests
for the Risk Assessment Workbench, run against a deployed environment.

```bash
cd tests/e2e
npm install
npx playwright install chromium
npx playwright test          # all projects; BASE_URL=... to target another environment
npm run report               # -> docs/qa/test-execution-report/index.html (+ PDF, CSVs, evidence)
```

| Project | Folder | What |
|---|---|---|
| `api` | `specs/api` | Reference data, intake, full assessment lifecycle to a committee decision, configuration, security |
| `ui-desktop` | `specs/ui` | Role navigation, intake, analyst workspace (all 7 tabs), committee voting, configuration, stored XSS |
| `ui-mobile` | `specs/responsive` | Pixel 7 layout: off-canvas nav, no horizontal overflow |
| `nfr` | `specs/nfr` | API latency and burst, page load and bundle size, axe-core WCAG 2.1 AA, keyboard operability |

## Conventions

- **Test-case metadata lives in the test.** `tc({ id, story, type, priority, steps, expected })`,
  `actual(...)` and `defect('DEF-xxx')` from `lib/harness.ts` become Playwright annotations. The report
  builder turns them into the catalogue and results.
- **Evidence.** `snap(page, label)` takes a full-page screenshot and `call(request, ...)` saves each API
  request/response as JSON. Both go to `evidence/<project>/<TC-ID>_<n>_<label>.*`.
- **Defect register.** `scripts/defects.mjs`. A defect's status on a run is derived from its linked tests.
- **Shared dev DB.** Data is synthetic and prefixed `[QA-E2E <RUN_ID>]`. Governance probes run on
  throwaway requests. Config values changed by a test are restored to baseline in `finally`.
- **Ordered lifecycles** (`02-assessment-lifecycle`, `ui/02`→`ui/04`) share ids through `lib/state.ts`,
  which survives the worker restart Playwright does after a failure.
