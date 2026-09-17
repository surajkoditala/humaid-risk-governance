# End-to-end tests (Playwright)

**Owner:** Shanthi Subramanian (QA / Test Automation)

API-level tests against the running Workbench. Complements — rather than overlaps —
`tests/Humaid.RiskGovernance.AdminUI.UnitTests` (xUnit + Moq, no I/O at all).

## Why two test stacks, and where each one belongs

| Layer | Tool | Why there and not elsewhere |
|---|---|---|
| Service invariants (scoring, quorum, the finalize gate, AI citation guards) | xUnit + Moq | No I/O, milliseconds, runs anywhere. Already 62 tests. |
| HTTP contract, **authorization**, wiring | **Playwright (here)** | HTTP is the level these actually live at — an authorization bug is invisible to a mocked unit test. |
| Database invariants (`audit_event` append-only trigger, `CHECK (residual_rating > 0)`) | .NET + Testcontainers *(not yet written)* | Playwright only sees HTTP. No endpoint attempts `UPDATE audit_event`, so no HTTP test can ever prove that trigger works. |

That third row is the gap to close next — it covers US-9.2, the repo's flagship governance claim.

## Run it

The suite needs the stack up. Three terminals:

```bash
bash ops/setup-local-db.sh                                                    # Postgres + Azurite (Docker)
dotnet run --project src/6-MockExternalSystems/Humaid.RiskGovernance.MockSystems
dotnet run --project src/1-API/Humaid.RiskGovernance.AdminUI.Web
```

Then:

```bash
cd tests/e2e
npm install
npm run test:api    # API + authorization (needs the API only)
npm run test:ui     # the three role journeys (also needs the webapp on :3000)
npm test            # everything — 18 tests
npm run report      # HTML report, including the "actual status" annotations
```

The `ui` project additionally needs the Vite dev server:

```bash
cd webapp && npm install && npm run dev
```

Override the target with `API_BASE_URL` rather than editing `playwright.config.js`.

If the API is not reachable the run aborts in `global-setup.js` with instructions. That guard is
load-bearing, not politeness — see the next section.

## Reading the results: `test.fail()` means "known gap", not "broken test"

Four tests in `api/authorization.spec.js` are annotated `test.fail()`. They assert the **secure**
behaviour, which the API does not currently implement. Playwright treats their failure as the
expected outcome, so the board stays green — and the moment somebody implements role checks, it
reports *"expected to fail, but passed"*. The fix announces itself. When that happens, delete the
annotation, not the test.

This is also exactly why `global-setup.js` hard-fails when the API is down: a `test.fail()` test
"passes" when it fails for *any* reason, including a connection refusal. Without the guard, running
this suite against nothing would produce a fully green board that proves nothing whatsoever.

## The finding these tests record

Two problems compound:

1. **There is no caller identity.** Every controller carries a bare `[Authorize]`, and in
   Development with `AUTH0_DOMAIN` blank, `DevBypassAuthHandler` authenticates *every* request —
   no header required — as one generic `system-dev` principal. `[Authorize]` currently proves
   nothing.

2. **The acting user is self-declared.** Every write endpoint takes the actor from the **request
   body** (`CastCommitteeVoteInput.CommitteeMemberUserId`, `FinalizeBody.ActorUserId`,
   `UpsertScoringConfigInput.ActorUserId`) rather than from the token —
   `DevBypassAuthHandler`'s own summary states this. Nothing checks the declared actor holds the
   role the action requires.

Together: **any caller can perform any action as any user.** This undermines US-8.2 AC5 (each
committee member's vote individually and accountably recorded), US-6.3 AC3 (the finalizing
analyst's identity "cannot be anonymous or attributed to 'system'"), and US-10.1 (scoring
configuration requires configuration privileges).

Scope, stated honestly: this is a Development-mode posture on synthetic data with no Auth0 tenant
yet — not a live breach. But it is **not** fixed by configuring Auth0 either, because the
authorization layer Auth0 would feed does not exist. Roles are seeded
(`ProductOwner | Analyst | CommitteeMember | Admin`, see `seed/seed_dev_users.sql`) and never read.

### Verified against a running stack (2026-09-12)

| Probe | Expected | Actual |
|---|---|---|
| `GET /api/User` with **no credential at all** | 401 | **200 — returns all 6 users** (name, email, role) |
| `POST /api/Committee/Vote`, actor = Product Owner | 403 | 400 (workflow) |
| `POST /api/Assessment/{id}/Finalize`, actor = Product Owner | 403 | 500 |
| `POST /api/Scoring/Config`, actor = Product Owner | 403 | 500 |

**No endpoint returned 403.** The declared actor's role was never consulted on any of them.

Precision matters on the last three: those probes used a deliberately non-existent id, so each was
rejected (or crashed) on *data* grounds before role could ever have mattered. They prove the role
check does not run first — they do **not** prove a request against a valid, committee-routed
assessment would be accepted. Confirming that end to end needs a seeded `PendingCommittee`
assessment, which is follow-up work.

Row 1 needs no such caveat and is the serious one: **the full user directory is readable with no
credential whatsoever.**

`api/authorization.spec.js` also keeps two *passing* validation tests. That is deliberate: the API
does validate input — a mitigation factor of `1.0` is refused — so the finding stays precisely an
authorization gap and is not overstated into "the API accepts anything".

## Second finding: unknown ids surface as 500

Found while probing the above. A well-formed but non-existent id reaches Postgres, and the
resulting exception escapes as a **500** instead of a 4xx:

```
Npgsql.PostgresException 23503: insert or update on table "scoring_config"
violates foreign key constraint "scoring_config_risk_category_id_fkey"
```

`BaseApiController.ExecuteAsync` does catch and log it, but its fallback is
`OperationResult.Failure` → 500 — so "you sent an id that does not exist" is reported to the caller
as "the server broke". `OperationResult` already has `NotFound` and `BadRequest` shapes built for
exactly this. Two `test.fail()` tests in the `Error handling` block record it.

## Layout

```
tests/e2e/
├── playwright.config.js     one `api` project; `ui` is the next step (see below)
├── global-setup.js          aborts the run if the API is down
├── fixtures/users.js        resolves seeded users by role (ids are re-generated per seed)
└── api/
    ├── smoke.spec.js        harness + contract: OperationResult envelope, seeded users, FFIEC categories
    └── authorization.spec.js
```

## The `ui` project — three role journeys

`ui/journeys.spec.js` runs the golden path as one continuous story, serial by design: a Product
Owner raises a change → an FCRM Analyst assesses and finalizes it → the Risk Committee votes. One
request moving through the workflow, not three unrelated fixtures.

Deliberately three, not thirty. UI tests are the most expensive evidence per hour in this repo —
they need Vite plus both .NET services plus Postgres — and a broad UI suite would mostly re-prove
what the 62 unit tests already cover far more cheaply.

Signing in needs no automation at all. While Auth0 is unconfigured, `DevUserContext.jsx` reads the
acting user straight out of `localStorage.devUserId`, so seeding that key before first paint *is*
the sign-in — the app's own mechanism, not a test-only backdoor.

### Selector notes, learned the hard way

| Thing | What works |
|---|---|
| Nav vs form buttons | `exact: true` is **mandatory** — the sidebar's "Submit Request" and the form's "Submit request" differ only by case, and Playwright's name matching is case-insensitive without it |
| Change type | Not a `<select>` — a base-ui combobox. Scope to `page.locator('form').first()`, because the header carries a third combobox (the user switcher) |
| Intake fields | Stable ids: `#title`, `#description`, `#details`, `#file`. Inputs have no `name` attributes |
| Workspace stages | `role="tab"`, not buttons: Categories, Policy, Extraction, Narrative, Scoring, Finalize, Audit |

## Two defects the UI suite proves

### DEF-004 — an empty assessment reaches the committee

The most serious finding in the product so far, and it was predicted by a unit test before being
confirmed in the browser.

`AssessmentService.CheckReadinessAsync` iterates over the *active mapped categories*. With none
mapped, both readiness loops are no-ops and `IsReady` is vacuously true — so the Finalize tab
reports **"Ready to finalize."**

Verified end to end on 2026-09-12: a change request with **zero categories, zero policy reliance
decisions, zero extracted fields, zero narrative and zero risk scores** was finalized, routed, and
appeared in the committee queue with a live **"Submit vote"** button. The committee is being asked
to take an accountable decision on a document containing nothing but a title.

That is the exact inverse of CLAUDE.md's central rule: *"don't let an AI output reach the committee
stage without a corresponding review gate in code."*

### DEF-006 — opening a workspace fails the first time, every time

`func_getOrCreateAssessment` does SELECT-then-INSERT with no `ON CONFLICT` and no lock:

```sql
SELECT id INTO v_id FROM assessment WHERE change_request_id = p_change_request_id;
IF v_id IS NULL THEN INSERT INTO assessment ...
```

React 18 StrictMode double-invokes effects in dev, so two POSTs race. Both read `NULL`, both
insert, and the loser violates `UNIQUE (change_request_id)` → Npgsql `23505` → **HTTP 500**. The
row *is* created, so a second click works.

**What is deliberately not tested:** a browser-level version — click Open, assert no 500 — was
written first and removed. It only fails when the two requests genuinely overlap, and it passed on
one full-suite run while failing in isolation. A `test.fail()` marker that oscillates is worse than
no test, because it trains everyone to ignore the signal. The kept version drives the race directly
with `Promise.all`, reproduces `23505` every time, and makes the stronger claim: this is a
stored-function defect, not a React artefact. Two analysts opening the same request simultaneously
would hit it in production, where StrictMode does not apply.

Fix for both halves: `INSERT ... ON CONFLICT (change_request_id) DO NOTHING`, then re-select.
