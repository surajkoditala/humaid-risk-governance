# End-to-end tests (Playwright)

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
npm run test:api
npm run report      # HTML report, including the "actual status" annotations
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

## Next: the `ui` project

Three role journeys, one per actor — Product Owner submits → Analyst assesses and finalizes →
Committee votes. That single golden path *is* the product demo and exercises the whole
human-in-the-loop chain end to end.

Keep it small on purpose. UI tests are the most expensive evidence per hour in this repo, they
need the Vite dev server plus both .NET services, and a broad UI suite would mostly re-prove what
the 62 unit tests already cover more cheaply. Three journeys, not thirty.

One thing genuinely in our favour: because `DevBypassAuthHandler` and `RequireAuth.jsx` both bypass
Auth0 in local dev, there is **no login flow to automate** — usually the most painful part of E2E
setup.
