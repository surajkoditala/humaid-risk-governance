# CI/CD Pipelines — Observability, Infrastructure & Application

**Status:** current as of 2026-09-29. Observability/IaC pipelines reflect [`.azure-pipelines/observability`](../../.azure-pipelines/observability) and [`.azure-pipelines/iac`](../../.azure-pipelines/iac) on `main`. Application pipelines (`workbench`, `mock-api`) reflect `.azure-pipelines/workbench` and `.azure-pipelines/mock-api` on `release/1.00` — that branch also carries `.azure-pipelines/README.md`, the source this section is drawn from.

---

## 1. Pipeline inventory

| Pipeline (Azure DevOps name) | File | Branch | Trigger | What it does |
|---|---|---|---|---|
| `gh-sre-watchdog-dev` | [`observability/sre-watchdog.yml`](../../.azure-pipelines/observability/sre-watchdog.yml) | `main` | Schedule — every 30 min | Queries Log Analytics for failure signals, has Claude classify them, opens/closes GitHub issues |
| `gh-infra-dev-pr-review` | [`iac/dev-pr-review.yml`](../../.azure-pipelines/iac/dev-pr-review.yml) | `main` | PR → `main`, paths `iac/environments/dev/**` | fmt/validate/lint/scan/plan gates + AI review; required GitHub check |
| `gh-infra-dev-deploy` | [`iac/dev-tf-deploy.yml`](../../.azure-pipelines/iac/dev-tf-deploy.yml) | `main` | Push → `main`, paths `iac/environments/dev/**` | `terraform apply` to dev, no manual approval |
| `gh-workbench-dev-pr-review` | `workbench/pr-review.yml` | `release/1.00` | PR → `release/1.00`, always runs | build, unit tests, webapp build, vuln audit, AI review; required GitHub check |
| `gh-workbench-dev-deploy` | `workbench/workbench.yml` | `release/1.00` | Push → `release/*` (excl. `release/dev`), paths `src/1..4/*`, `tests/*`, `webapp/*` | Build/push image, Trivy scan, deploy to dev Container App |
| `gh-mock-api-dev-pr-review` | `mock-api/pr-review.yml` | `release/1.00` | PR → `release/1.00`, always runs | generated-SQL drift check, build, vuln audit, AI review; required GitHub check |
| `gh-mock-api-dev-deploy` | `mock-api/mock-api.yml` | `release/1.00` | Push → `release/*` (excl. `release/dev`), paths `src/6-MockExternalSystems/*` | Build/push image, Trivy scan, deploy to dev Container App |

All seven run in Azure DevOps against a GitHub-hosted repo. The IaC/observability set authenticates to Azure via the `azure-cloud` Workload Identity Federation service connection; the app set uses its own `azureSubscription`/ACR service connection. All PR and AI-review steps share the `ai-review-secrets` variable group (`CLAUDE_CODE_OAUTH_TOKEN`, `GITHUB_PAT`).

---

## 2. SRE Watchdog (`gh-sre-watchdog-dev`)

Runs unconditionally every 30 minutes — not push/PR triggered — as a leading indicator ahead of the native scheduled-query email alerts in [`main.monitor.tf`](../../iac/environments/dev/main.monitor.tf).

**Steps:**
1. **`query.sh`** — read-only `az monitor log-analytics query` calls for four signals against the dev Log Analytics workspace:
   - `failed_request_burst`, `unhandled_exceptions` — hard-threshold, last 15 min. Mirror the two `azurerm_monitor_scheduled_query_rules_alert_v2` resources in `main.monitor.tf`, so the same condition also gets an AI-narrated GitHub issue, not just an email.
   - `failure_rate_trend`, `exception_count_trend` — trend/anomaly, last 3h, via Kusto `series_decompose_anomalies`. Fire *before* a hard threshold breaches.
   - Each query is individually timeout-bounded (`timeout -k 10`) and the log-analytics CLI extension is pre-installed once up front, outside the per-query budget.
2. **`summarize.sh`** — feeds the raw JSON to Claude (`rules.md` + schema, no tool access, no repo/infra access) to classify each signal `critical` / `warning` / `ok` and write a plain-language summary. Never fails the build — no signals or an AI outage just means no verdict this run.
3. **`post.sh`** — opens one GitHub issue per non-`ok` condition (label `sre-watchdog`), or closes it with a "Recovered" comment once the condition clears. Issue open/closed state *is* the dedupe store — an already-open issue gets no repeat notification.
4. Publishes signals + verdict as a build artifact for the audit trail.

**Security:** the query step's service connection can only run read queries. `post.sh` (holds `GITHUB_PAT`) never sees the raw telemetry — `summarize.sh` (which does read untrusted log/exception content) doesn't have that token. `rules.md` explicitly tells Claude to treat signal content as untrusted data, never instructions.

**Hardening fixed in this branch's work:**
- Query step could hang indefinitely — root cause was `az`'s detached telemetry-upload subprocess inheriting the script's stdout pipe, so a `$(...)` capture never returned even though `az` itself had finished. Fixed by disabling telemetry (`AZURE_CORE_COLLECT_TELEMETRY=0`) plus `timeout -k 10` as a second line of defense.
- `run_query`'s jq filter was missing `-n`, which silently produced no output instead of running once — never surfaced because the telemetry hang killed the script first.
- Trend signals were flagging degenerate zero-value points (fresh workspace, no real baseline yet) as anomalies — fixed by requiring `isnotnull(score) and FailedPct/ExceptionCount > 0` before a trend row counts as a real signal.

---

## 3. IaC PR Review (`gh-infra-dev-pr-review`)

Required GitHub status check on `main` for any PR touching `iac/environments/dev/**`. Hard gates run cheapest-first so a bad PR fails fast:

`terraform fmt` → `init` → `validate` → TFLint (error-severity) → Trivy (HIGH/CRITICAL) → `terraform plan` → AI verdict (`BLOCKING_ISSUES`).

Checkov and Trivy MEDIUM stay informational (`--soft-fail` / non-gating) — findings are published as JSON artifacts either way. Claude reviews the Trivy/Checkov JSON plus the plan text and is instructed to be **diff-aware**: both scanners cover the whole config, so a finding only affects the verdict if it's on a resource this specific plan creates/modifies; unrelated pre-existing findings are reported as a count, not itemized, to avoid repeating the same static list on every unrelated PR. On `NEEDS_ATTENTION`/`BLOCKING_ISSUES` the PR author is `@mention`ed in the posted comment.

---

## 4. IaC Deploy (`gh-infra-dev-deploy`)

Push-only (`pr: none`), triggers on merge to `main`. Trusts `dev-pr-review.yml`'s gate — no manual approval step. `terraform plan` then `apply`, plan/apply output published as an artifact. On failure, comments on the merged PR (or the commit, for a direct push) `@mention`-ing the author; this step never fails the build itself — the build is already failed, and a notification hiccup shouldn't add noise.

---

## 5. Workbench & Mock API PR Review (`gh-workbench-dev-pr-review`, `gh-mock-api-dev-pr-review`)

Both required GitHub status checks on `release/1.00`. Neither uses a path-filtered trigger — a required check has to post on *every* PR or the merge blocks forever waiting on a check that never appears — so both pipelines always fire, and a "Detect relevant path changes" step diffs the PR against its target branch and sets `runFull`; when the PR doesn't touch that component's scope, every gate step is skipped (fast, cheap green).

**Workbench** (`src/1-API`, `src/2-Infrastructure`, `src/3-Service`, `src/4-Persistence`, `tests`, `webapp`): build API (`dotnet build`) → unit tests → build `webapp` (Vite, Node 22.x) → dependency vuln audit (`dotnet-vuln-check.sh` + `npm audit --audit-level=high`) → Semgrep (informational only) → shared AI review template.

**Mock API** (`src/6-MockExternalSystems`): checks `deploy_all.sql` isn't stale relative to its generator (`generate_deploy_all.sh`, `LC_ALL=C`-pinned for deterministic ordering) → build → dependency vuln audit → Semgrep (informational) → shared AI review template. No test project exists for it yet.

Both end with `templates/ai-review.yml` — the same two-step pattern as the IaC pipeline (`review.sh` diffs the PR against its base and asks Claude, scoped to that component's paths and `<component>/prompt.md`; `post.sh` comments on the PR and fails the build on `BLOCKING_ISSUES`). Hard gates: build, tests (Workbench), SQL drift (Mock API), vulnerable dependencies, AI blockers. Semgrep is informational only, published as a build artifact.

---

## 6. Workbench & Mock API Deploy (`gh-workbench-dev-deploy`, `gh-mock-api-dev-deploy`)

Push-triggered (`pr: none`) on `release/*` branches (excluding `release/dev`) that touch the component's `src/` paths. Each has one `dev` stage today (`environments/dev.yml`); a future `test`/`prod` stage would live alongside it.

Per component, the stage:
1. Builds the Docker image from the repo root (`--pull --no-cache`) and pushes it to the shared dev ACR, tagged `<version>-<buildId>` (pipeline build ID, not the git SHA), then polls ACR until the tag is visible.
2. Runs Trivy (`aquasec/trivy:0.50.2`) against the image — **fails on any HIGH/CRITICAL finding** (an `.trivyignore` at the repo root can list accepted exceptions; none exists today). Both the JSON and readable reports are published as build artifacts regardless of outcome.
3. Saves the image as a build artifact (skipped on PR builds, which never reach this stage).
4. Deploys via the shared `id-ca-gh-dev` user-assigned managed identity (granted `AcrPull` on the registry in `iac`) — `az containerapp update --image ...` points the Container App at the new tag with no registry password; a revision that fails to provision fails the step.
5. On any step failure, the partially-tagged image is deleted from ACR so a failed build never leaves a dangling tag.

Both components share the `azure-cloud` service connection (same WIF identity as the IaC deploy pipeline) and the `devResourceGroup`/`devUaiName`/`acrName` variables in each component's `templates/variables.yml`.

---

## 7. Shared building blocks

- **`azure-cloud` service connection** — Workload Identity Federation; every IaC/observability pipeline that touches Azure authenticates through it, no client secret or storage-account key anywhere. The Workbench/Mock API deploy pipelines share this same identity for their `AcrPull`-scoped deploy step.
- **`ai-review-secrets` variable group** — `CLAUDE_CODE_OAUTH_TOKEN` (from `claude setup-token`, runs on the Claude subscription, not metered API billing) and `GITHUB_PAT` (repo scope). Used by all four PR pipelines' AI-review steps and by the watchdog. A pipeline must be explicitly authorized to use the group in ADO (Library → Pipeline permissions) or its first run stalls on a "Permit" click.
- **Claude Code CLI** — installed fresh per run (`npm install -g @anthropic-ai/claude-code`) in the watchdog summarizer and in all three AI-review pipelines (IaC, Workbench, Mock API); each invocation is scoped to a single non-interactive `-p --max-turns 1` call with no filesystem/tool access beyond what the step explicitly reads in.
- **Shared AI-review template** (`templates/ai-review.yml` + `scripts/ai-review/{review.sh,post.sh,rules.md,schema.json}`) — one implementation of "diff PR → ask Claude → comment → gate on BLOCKING_ISSUES", parameterized by title/scope/prompt, used by both Workbench and Mock API. The IaC pipeline follows the same read/post token-separation pattern inline rather than via this template.
- **Trivy** — used both as a config scanner (IaC, against Terraform) and an image scanner (Workbench/Mock API deploy, against the built container); HIGH/CRITICAL is a hard gate in both cases.

---

## 8. Security & safety posture

- **Least-privilege tokens per step:** the step that reads potentially-untrusted content (telemetry, PR diffs) never holds `GITHUB_PAT`; the step that posts to GitHub never reads that raw content. Same separation in `templates/ai-review.yml` (`review.sh` vs `post.sh`) as in the IaC pipeline.
- **Required checks always trigger:** Workbench/Mock API PR pipelines have no path filter on their trigger (only path-filtered gate steps), because a path-filtered *trigger* would mean the required GitHub check never posts — and never-posted required checks block merges forever, not just for out-of-scope PRs.
- **Fail-closed on ambiguity, fail-open on AI unavailability:** an unparseable AI verdict defaults to `NEEDS_ATTENTION` (never silently `LOOKS_GOOD`) across all three AI-review pipelines; an AI outage on the watchdog, or any deploy pipeline, just skips notification/verdict rather than blocking.
- **Read-only where possible:** the watchdog's Azure calls are 100% read (`az monitor log-analytics query`); the IaC deploy and app deploy pipelines are the only ones whose service-connection identity performs writes (`terraform apply`, `docker push`, `az containerapp update`).
- **Prompt-injection awareness:** every AI-review prompt (watchdog `rules.md`, IaC review prompt, shared `scripts/ai-review/rules.md`) explicitly instructs Claude to treat scanned data as untrusted and never follow instructions embedded in it. The AI review step itself only has Read/Grep/Glob inside the checkout — never write access, never secrets.
- **No dangling artifacts on failure:** both the IaC PR pipeline's Trivy step and the app deploy pipelines delete a partially-tagged/pushed image or fail cleanly rather than leaving inconsistent state in ACR.

---

## Revision log

- **2026-09-29** — initial version, covering the observability (SRE watchdog) and IaC (PR review + deploy) pipelines built on `main`.
- **2026-09-29** — added the application pipelines (Workbench, Mock API — PR review + image build/scan/deploy) from `release/1.00`, so this doc covers all seven pipelines in the Azure DevOps project.
