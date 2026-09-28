# QA: end-to-end test campaign generation (Claude Code)

**Stage:** Testing (SDLC stage 4) · **Owner:** QA · **Tool:** Claude Code (Opus) driving Playwright

## Prompt given

> https://ca-gh-hrg-workbench-dev.jollyplant-1cbb4459.eastus2.azurecontainerapps.io/ — this is up and running.
> I need you to perform complete testing and provide test cases and test results. Use Playwright for
> complete UI testing and do all functional + API + all other testing. Need test cases + execution +
> report + all screenshots + evidences.

## How the agent approached it

1. **Context first, not the UI.** It read `CLAUDE.md`, `docs/requirements/user-stories.md` (the ACs are the
   test oracle), every controller, DTO and page component, and the stored functions behind scoring,
   committee, reliance and attachments. That is how it predicted defects before running anything, e.g. the
   residual-risk formula and its range guards, the vote upsert, and the extraction tab posting `fileName`
   as the document text.
2. **Probe the live environment** with plain HTTP (health, auth, headers, `/openapi/v1.json`) and one
   exploratory browser pass (ARIA snapshot) to learn real selectors.
3. **One source of truth for test cases.** Each test calls `tc({...})` (ID, story, type, priority, steps,
   expected) and `actual(...)`, and optionally `defect(...)`. `scripts/build-report.mjs` generates the
   catalogue, results CSV and HTML/PDF report from those annotations, so documentation can't drift from
   the executed code.
4. **Deterministic vs probabilistic.** AI touchpoints (propose, extract, draft) are asserted on
   *structure and grounding* (FFIEC-only categories, citations present, fields have confidence/review
   flags, section status labels), not exact wording.
5. **Shared-environment hygiene.** All data is synthetic and prefixed `[QA-E2E <run>]`. Destructive
   governance probes (empty-assessment finalize, invalid votes, non-member votes) run on throwaway
   "probe" requests, so the main lifecycle still reaches a real decision. Config values are written back
   to their baseline in `finally` blocks.
6. **Resilient lifecycle.** Playwright restarts the worker after a failed test, so ids shared between
   ordered lifecycle steps are persisted in `results/state-<run>.json` (`lib/state.ts`).

## Output

- Suite: `tests/e2e/` (API, UI desktop, UI mobile, NFR: performance, accessibility, security).
- Deliverable: `docs/qa/test-execution-report/` (HTML + PDF report, CSVs, screenshots, JSON evidence,
  Playwright traces).
