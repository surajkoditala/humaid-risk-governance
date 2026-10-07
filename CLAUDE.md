# Project Context — Genius Hacks Q3 2026: Risk Assessment Workbench
## Team: HumAId Risk Governance

This file gives Claude Code full context on this hackathon project. Read this before starting any work. A companion file, `docs/requirements/user-stories.md`, has the full epics/acceptance criteria — read that too before writing code against any specific feature.

---

## Event
- **Myridius Genius Hacks Q3 2026** — mandatory hackathon for Level 2 (Practitioner) AI Maturity badge.
- Registration deadline: 2 September 2026 (done — team already registered)
- Submission deadline: 30 September 2026 (repo + presentation, both due end of day; commits after this are not assessed)
- No prompt-to-app generators allowed (Lovable, Bolt, v0, Replit Agent). AI-assisted coding in a real codebase (Claude Code, Copilot, Cursor) is fully encouraged and expected.
- Commit history is evidence — commit incrementally with meaningful messages, not one giant dump.

## Team
**Team name:** HumAId Risk Governance
**Size:** 4

| Role | Owns |
|---|---|
| Dev 1 (backend/.NET tech lead) | Core domain, Assessment/Scoring module, AI orchestration layer (`RAW.AI`) |
| Dev 2 | Intake, Workflow, Committee module, API layer, EF Core setup |
| QA | `/tests` (unit/integration), `/evals` (AI output quality evaluation — 10% judging weight) |
| DevOps | `/ops` (Terraform in `ops/iac/`, local Docker Compose), Dockerfiles, Azure DevOps CI/CD (`.azure-pipelines/`), monitoring/observability (Operations stage) |

## The Problem Statement (given, deliberately incomplete — expansion is graded)

**Client:** A large national bank (~$500B assets) — consumer banking, commercial banking, payments, wealth management. Heavily supervised on financial crime risk controls.

**Business problem:** Whenever a business unit wants to launch a product, add a feature, change a process, onboard a vendor, enter a new geography, or open to a new customer segment, the Financial Crimes Risk Management (FCRM) function must assess the financial crime risk before go-live. Outcome: approved / rejected / deferred / approved with conditions.

**Current pain:** Runs on email/Word/Excel/SharePoint. Assessment takes 15–20 business days. Two analysts can reach different conclusions on the same change. Reconstructing the reasoning behind a past rating (for examiners) is slow and incomplete.

**What to build — "Risk Assessment Workbench":** One governed platform carrying a change request from intake → assessment → committee decision. Workflow, scoring, and record-keeping are automated. AI is applied specifically to: mapping the request to risk categories, finding relevant policy, extracting structure from submitted documents, and drafting the assessment narrative for human review.

**Three user roles:** Product Owner (raises the change), FCRM Analyst (finalizes assessment, owns config), Risk Committee (votes on final decision).

**Critical rule: the system prepares, humans decide. Nothing is auto-approved or auto-rejected.**

**Constraints:**
- Risk decomposition must be grounded in a real, published, citable supervisory framework — not invented.
- Controls mitigate risk, never eliminate it — residual risk must never reach zero, enforced at both calculation time and configuration time.
- A human can override any AI output; must state a reason; both original and override are retained.
- Synthetic data only. No connection to any real system.

## What Must Be Demonstrated — 6 SDLC stages, AI applied across all
1. Requirements — expand the brief, research to fill gaps
2. Design — architecture, data model, UX, tool choices
3. Development — code gen, data engineering, agent orchestration
4. Testing — validation, QA, test automation
5. Deployment — production deployment approach
6. Operations — monitoring, observability, continuous improvement

## Judging Weights
30% AI harness & orchestration · 20% SDLC automation across all 6 stages · 15% Human-in-the-loop & governance · 10% Evaluation framework · 10% Context engineering & requirement expansion · 5% Production readiness · 5% Token efficiency · 5% Engineering judgement (deterministic vs probabilistic, when NOT to use an LLM).
Not evaluated: which AI tool used, coding speed, raw output volume, polish without real engineering underneath.

---

## Architecture Decision: Modular multi-tier application (NOT microservices)

**Rationale:** 4-person team, 5-week timeline. Production scalability is only 5% of the score; AI harness/orchestration is 30%. Effort belongs in the AI layer, not distributed-systems overhead. Clean module boundaries make it easy to defend and easy to split later if asked. The one deliberate exception is Mock Systems, which stands in for the bank's external systems and is therefore its own separately deployed service, not part of the Workbench.

The repo as built (5-layer Clean Architecture; `docs/architecture/architecture-mapping.md` maps it onto the originally suggested `RAW.*` layout):

```
Humaid.RiskGovernance.AdminUI.slnx
├── src/
│   ├── 1-API/Humaid.RiskGovernance.AdminUI.Web/                 → ASP.NET Core Web API: controllers, Auth0 JWT validation; serves the built webapp from wwwroot in its image
│   ├── 2-Infrastructure/Humaid.RiskGovernance.AdminUI.Infrastructure/ → interfaces, models, OperationResult<T> — no implementations
│   ├── 3-Service/
│   │   ├── Humaid.RiskGovernance.AdminUI.Services/              → business logic (intake, assessment, scoring, committee, audit, config, document processing)
│   │   └── Humaid.RiskGovernance.AdminUI.AI/                    → AI orchestration — IChatCompletionClient (Anthropic or Azure AI Foundry)
│   ├── 4-Persistence/
│   │   ├── Humaid.RiskGovernance.AdminUI.DA/                    → Dapper repos — every query calls a stored routine
│   │   └── Humaid.RiskGovernance.AdminUI.DB/                    → schema/functions/seed + generated deploy_all.sql
│   └── 6-MockExternalSystems/Humaid.RiskGovernance.MockSystems/ → mock CRM/Core Banking/Vendor Mgmt — separate service, own schema
├── webapp/                      → 5-Presentation: React + Vite SPA (webapp.esproj, built with the solution)
├── tests/Humaid.RiskGovernance.AdminUI.UnitTests/  → QA — xUnit + Moq
├── evals/                       → QA — AI output quality measurement against fixed datasets
├── ai/                          → prompts, agent docs, research, data-generation, langgraph/ demonstrator
├── harness/                     → dev tooling: dev_harness (LangGraph diff review), ba_harness, test_case_harness
├── docs/
│   ├── requirements/            → user-stories.md
│   ├── architecture/            → architecture / infrastructure / pipeline mappings, C4, diagrams, Auth0 setup
│   ├── governance/              → human-in-the-loop gates, access-control matrix, roles and screens
│   └── qa/                      → requirement coverage, test execution report
├── ops/                         → local Docker Compose, setup-local-db.sh, proxy certs, Azure deployment notes (README.md)
│   └── iac/                     → Terraform: modules/ (10 reusable modules) + environments/dev/
├── .azure-pipelines/            → Azure DevOps pipelines: iac, workbench, mock-api, observability, harness
└── README.md                    → setup, walkthrough, current state
```

**Audit trail requirement:** must be write-once/append-only at the data layer (not just app-level permissions) — this is a technical/architecture constraint, not just a UI feature. Factor this into the Audit module's data store design from day one.

## Tech Stack
- Backend: C# / .NET 10 Web API; data access through Dapper calling PostgreSQL stored functions (no EF Core, no ad-hoc SQL)
- Frontend: React 19 + Vite, Auth0 (`@auth0/auth0-react`); in Azure the built SPA is served from the Workbench image
- Database: PostgreSQL 16 (Azure Database for PostgreSQL Flexible Server in Azure; Docker locally)
- AI: `AI_PROVIDER` = `Anthropic` (local default) or `AzureFoundry` (dev in Azure)
- Deployment: Azure Container Apps
- Containerization: a Dockerfile per service plus `ops/docker-compose*.yml` (local); Terraform in `ops/iac/` (Azure)
- AI coding tool: Claude Code — used to direct/orchestrate development, not a prompt-to-app generator

---

## Risk Framework — Grounded in FFIEC BSA/AML Examination Manual (citable: bsaaml.ffiec.gov)

Four core risk categories (do not invent categories — these are the citable source):

| Category | Sub-factors |
|---|---|
| Products & Services | ACH, wire transfers, foreign exchange, trade finance, private banking, prepaid access, correspondent banking |
| Customers & Entities | Cash-intensive businesses, PEPs, non-resident aliens, MSBs, NGOs/charities, shell companies, beneficial ownership complexity |
| Geographic Locations | FATF high-risk/monitored jurisdictions, OFAC sanctioned countries, domestic HIFCAs |
| Delivery Channels | In-person/branch vs. online/non-face-to-face, third-party agents, correspondent relationships |

**Change-request-type → primary category mapping:**
New product → Products/Services + Customers · Feature → Products/Services · Process change → Delivery Channels · Vendor onboarding → Customers/Entities + Delivery Channels · New geography → Geographic (heaviest) + Products/Services · New customer segment → Customers/Entities (heaviest).

**Scoring principle:** `Residual Risk = Inherent Risk − (Control Effectiveness × Mitigation Factor)`, where the mitigation factor is capped below 1.0 so residual risk can never reach zero — enforce this both in the scoring calculation AND as a validation rule when analysts configure control mitigation values (reject config that would let residual hit zero).

**Open question (needs team decision):** should the framework be hardcoded (single framework, e.g. FFIEC only) or configurable per jurisdiction/business line (supports multiple named frameworks)? This changes `RiskCategory` from a simple enum to a DB-driven config table. Default assumption if undecided: start with FFIEC hardcoded as enum for MVP, document the config-driven alternative as a noted extension point (defensible either way, but must be a stated decision, not an accident).

## Data Strategy — three different things, don't conflate them

1. **Risk framework/categories** — static, one-time research, hardcoded or configured. No live fetch.
2. **Policy corpus for AI retrieval (RAG)** — download real public FFIEC/FATF documents once, chunk + embed into pgvector or Azure AI Search. AI queries this local corpus at assessment time; no live internet calls during operation.
3. **Bank data (customers, transactions, change requests)** — 100% synthetic, generated by the team (e.g. Bogus library or AI-generated). Never connects to any real system — this is a hard hackathon constraint.

---

## User Stories — see `docs/requirements/user-stories.md`

Prepared by the team's BA (epics 1–10), plus Epics 11–13 raised by QA on 17 Sep 2026 (Access Control, Deployment & Operations, Non-Functional Requirements; also US-9.3, audit export), Epic 14 added from the Platform Ecosystem Diagram, Epics 15–18 (infrastructure, pipelines, observability) added from the IaC and pipeline work — see the section below — and Epic 19 (SLA tracking) raised by QA on 24 Sep 2026. Epic and story IDs match the Azure Boards work items. Given/When/Then acceptance criteria throughout. Structure:

1. Change Request Intake
2. Risk Categorization & Framework Mapping **[AI]**
3. AI-Assisted Policy Research **[AI]**
4. AI-Assisted Document Extraction **[AI]**
5. AI-Drafted Risk Assessment **[AI]**
6. Analyst Review, Edit & Override (human override is first-class everywhere — never a silent overwrite, always requires a reason)
7. Risk Scoring Engine (residual risk must always be > 0)
8. Committee Review & Voting
9. Immutable Audit Trail (append-only at data layer)
10. Platform Configuration (analyst-owned, no-code scoring/workflow tuning)
11. Access Control (role-based permissions enforced at the API, not just the UI) — delivered: see `docs/governance/access-control-matrix.md` for the role-by-action matrix AC4 asks for
12. Deployment & Operations (schema deploy, container build/scan, observability)
13. Non-Functional Requirements (retention, in-tenant model calls)
14. Mock External Systems & Data Ingestion (mock CRM/Core Banking/Vendor Management as a separate service; Data Ingestion Layer is the only path to it; committee decisions push back to the source system — deterministic, no AI call)
15. Terraform Modules for Azure Infrastructure (10 reusable modules under `ops/iac/modules`)
16. Dev Environment Infrastructure Set Up (the dev environment provisioned from those modules)
17. Set Up DevOps CI/CD Pipelines (infrastructure and application pipelines in Azure DevOps) — US-17.4 and US-17.8 are tagged **[AI]**: AI reviews pull requests in the pipeline, not in the product
18. Observability (application telemetry to Application Insights — US-18.1 — and the SRE watchdog agent — US-18.2 — are both delivered; see the Observability section below)
19. SLA Tracking and Breach Notification (business-day SLA targets per stage and change type, elapsed-time tracking and the SLA view are delivered — US-19.1, 19.2, 19.5; distribution lists and breach email — US-19.3, 19.4 — need an email provider and a scheduled job and are still open). Deterministic arithmetic, no AI; a breach only informs and never changes a status or decides anything.
20. AI Orchestration State & LangGraph Evaluation (a shared state object across the AI touchpoints, plus a scoped LangGraph demonstrator — see `docs/architecture/langgraph-evaluation.md` for why full adoption isn't recommended for this submission, and its own epic for the risk that this doesn't finish by 30 Sep). Numbered 20, not 19 — Epic 19 (SLA Tracking) exists in Azure Boards only, not yet in `user-stories.md`.

**Open questions logged by the BA — resolve with team before locking design:**
1. Do Product Owners see analyst scoring rationale, or only status?
2. Is the risk framework configurable per jurisdiction/business line, or single fixed framework?
3. Does a scoring override need secondary/senior-analyst sign-off before finalization?
4. Is committee decisioning majority vote, unanimous, or chair-decided?
5. Who can approve scoring/workflow configuration changes — self-service or manager approval?

Every AI-touchpoint epic (2, 3, 4, 5) pairs with a human review/override story by design — this directly evidences the 15% "human-in-the-loop and governance" judging criterion, so preserve that pairing in implementation; don't let an AI output reach the committee stage without a corresponding review gate in code.

---

## Infrastructure, DevOps & Observability — see Epics 15–18 in `docs/requirements/user-stories.md`

Orientation only, as of 5 Oct 2026; the acceptance criteria in the user stories are the spec. This section is separate from the application architecture above.

### Where the code lives
- Infrastructure lives in `ops/iac/` (Terraform) with its pipelines in `.azure-pipelines/iac/`; the application lives in `src/`, `webapp/`, and `tests/`, with its pipelines elsewhere in `.azure-pipelines/`. Both `main` and `release/1.00` carry the whole tree.
- Infrastructure changes land on **`main`** (the infra PR review and deploy trigger on it, and the SRE watchdog is scheduled from it); application changes land on **`release/1.00`** (the app PR reviews run on PRs into it, and a push to `release/*` builds and deploys the images).
- PRs into `release/*` can only be merged with a merge commit (GitHub ruleset `release-merge-commit-only`). Merge `release/1.00` → `main` with a merge commit too: squashing splits the two histories and causes add/add conflicts on the next release merge.
- The repo is on GitHub; the pipelines run in Azure DevOps.

### Infrastructure as Code (`ops/iac/`, Epics 15–16)
- Terraform `~> 1.8` (pipelines install 1.12.2), azurerm `>= 4.0, < 5.0`. Remote state: azurerm backend, resource group `rg-gh-tf-dev`, storage account `stghtfstatedev01`, container `tfstate`, key `dev/terraform.tfstate`.
- **`ops/iac/modules/`** — ten reusable modules, each with README, Intro, CHANGELOG, and examples: resource group, virtual network, private DNS zone, key vault, storage account, PostgreSQL, Log Analytics workspace, container registry, container apps environment, container apps. The modules validate the required tags (`business_unit`, `customer`, `environment`, `product`, `owner`, `region`), follow the `<type>-<product>-<environment>` naming, and offer optional locks, RBAC, private endpoints, and diagnostic settings.
- **`ops/iac/environments/dev/`** — one configuration, one `main.<resource>.tf` file per resource, variables in `variables.*.tf`, values in `parameters.*.auto.tfvars`. It provisions: resource group; VNet `10.12.0.0/16` with subnets `snet-pep-dev-01` and `snet-cae-dev-01` and one NSG each; six private DNS zones; Key Vault; Storage Account (four private endpoints); PostgreSQL Flexible Server with database `risk_governance_db`; Log Analytics workspace and Application Insights; container registry; user-assigned identity `id-ca-<product>-<environment>` with AcrPull; a VNet-integrated container apps environment (Consumption profile); and two container apps.
- **Container apps:** `gh-hrg-workbench` (Workbench UI, external ingress, port 8080) and `gh-hrg-mockapi` (Mock API, internal-only ingress, so only the Workbench inside the environment can reach it). Terraform creates them with a placeholder image (`hello-dotnet-http:v1`); the real images are deployed by `workbench/workbench.yml` and `mock-api/mock-api.yml`, and Terraform ignores later image changes.
- **Decisions and constraints to keep:** default region `eastus2`; PostgreSQL is in `centralus` because the subscription cannot provision it in `eastus2`, and its private endpoint stays in `eastus2` with the VNet. Data services sit behind private endpoints with network rules set to deny by default. Dev is cost-conscious on purpose: Consumption plan only, no high availability, no geo-redundant backup, no resource group lock, and diagnostic settings and Log Analytics attachments left disabled (commented out in Terraform).
- **Secrets never go in code or tfvars.** The PostgreSQL admin password is generated by Terraform at apply time, and the apps reach PostgreSQL, Key Vault, and Storage through managed identities (Entra), not passwords.
- **App config in Azure** comes from container app env vars set in `ops/iac/environments/dev/locals.tf`: `AZURE_POSTGRESQL_ENDPOINT` (passwordless connection string, Entra token), `BLOB_STORAGE_SERVICE_URI`, `PEP_KEY_VAULT`, `APPLICATIONINSIGHTS_CONNECTION_STRING`, `MOCK_SYSTEMS_BASE_URL`, `CORS_ALLOWED_ORIGINS__0`, and `AI_PROVIDER=AzureFoundry` with `FOUNDRY_PROJECT_ENDPOINT`/`FOUNDRY_MODEL_DEPLOYMENT`. The only secrets, `ANTHROPIC-API-KEY` and `FOUNDRY-API-KEY`, are read from Key Vault at startup (allow-listed in `Program.cs`). Each app's system identity holds Key Vault Secrets/Certificate User and Storage Blob/Queue Data Contributor.

### CI/CD pipelines (`.azure-pipelines/`, Epic 17)
| Pipeline | File | Runs when | Hard gates |
|---|---|---|---|
| Infra PR review | `iac/dev-pr-review.yml` | PR to `main` touching `ops/iac/environments/dev` | `terraform fmt`, init, validate, TFLint (errors), Trivy HIGH/CRITICAL, Terraform plan, AI review `BLOCKING_ISSUES` |
| Infra deploy | `iac/dev-tf-deploy.yml` | push to `main` touching `ops/iac/environments/dev` | plan + apply to dev, no manual approval (the PR review is the required check) |
| Workbench PR review | `workbench/pr-review.yml` | PR to `release/1.00` touching Workbench paths | build, unit tests, webapp build, dependency audit, AI review blockers |
| Mock API PR review | `mock-api/pr-review.yml` | PR to `release/1.00` touching `src/6-MockExternalSystems` | `deploy_all.sql` drift, build, dependency audit, AI review blockers |
| Image build, scan, deploy | `workbench/workbench.yml`, `mock-api/mock-api.yml` | push to `release/*` (not `release/dev`) touching the component's paths | Docker build, push to ACR, Trivy HIGH/CRITICAL, `az containerapp update` to dev |
| Dev harness report | `harness/dev-harness.yml` | PR to `release/1.00` (draft, not a required check) | none — informational LangGraph review report |
| SRE watchdog | `observability/sre-watchdog.yml` | every 30 minutes, from `main` | none — opens, updates, and closes GitHub issues (see Observability) |

- Informational only (never fail a build): Trivy MEDIUM, Checkov (soft-fail, skipped checks are justified in `.azure-pipelines/iac/.checkov.yml`), TFLint warnings, Semgrep.
- **AI review:** the infrastructure pipeline reviews the scan results and the plan; the application pipelines share `templates/ai-review.yml` and `scripts/ai-review/` (`rules.md`, `schema.json`, `review.sh`, `post.sh`) plus a per-component `prompt.md`. The reviewer is read-only inside the checkout, and only a blocker fails the build. An AI outage never blocks a PR.
- **Access to Azure** goes through the `azure-cloud` service connection (Workload Identity Federation, no stored client secret). Secrets live in the variable groups `ai-review-secrets` (`CLAUDE_CODE_OAUTH_TOKEN`, `GITHUB_PAT`) and `checkov-secrets`; never commit them.
- Failure and attention notifications @mention the PR author on GitHub.

### Observability (Epic 18)
- **US-18.1 is delivered.** Both container apps' `APPLICATIONINSIGHTS_CONNECTION_STRING` env var points at the dev Application Insights instance, and both `Program.cs` files register `AddOpenTelemetry().UseAzureMonitor(...)` conditional on that variable being set — so requests, outbound calls, and errors are flowing now that real images are deployed (see Epic 17). Resource-level diagnostic settings (Key Vault, Storage, PostgreSQL, the container apps environment) stay disabled — a deliberate cost-control decision, not a gap.
- **US-18.2 is delivered, in two layers.** Native Azure Monitor alerts in `ops/iac/environments/dev/main.monitor.tf` (Smart Detection failure anomalies, plus scheduled query rules for a failed-request burst and unhandled exceptions) email the team through the `ag-sre-*` action group. On top of that, `observability/sre-watchdog.yml` runs every 30 minutes: `scripts/sre-watchdog/query.sh` checks the same two threshold conditions plus two trend/anomaly conditions as a leading indicator, Claude turns the rows into a plain-language verdict, and `post.sh` keeps one GitHub issue per condition (opened, updated, closed — the issue state is the dedupe store). The watchdog is read-only: it only runs `az monitor log-analytics query`.
- US-12.2 (build and publish images) and US-12.3 (observe an environment) in Epic 12 are expected to be largely covered by Epics 17 and 18.

### Azure DevOps Boards (how to add or change work items)
- Organization `https://dev.azure.com/Myridius-Insurity`, project `humaid-risk-governance`, Scrum process: **Epic → Product Backlog Item** (no Feature level). Area and iteration stay at the project root.
- Title format `Epic N - Name` and `US-N.M - Title`. Description: `<p>As a DevOps Engineer, I want …, so that ….</p>`. Acceptance criteria go in the Acceptance Criteria field as `<ul><li>Given … when … then …</li></ul>`. Priority 2, Value Area Business, State New. Tags: one category tag plus one epic tag, separated by `; `.
- **Write items as work for someone to pick up:** forward-looking ("set up", "create"), never describing something as already existing.
- Boards IDs (they differ from the epic numbers): Epic 15 = 52 (stories 53–62), Epic 16 = 63 (64–76), Epic 17 = 77 (78, 80–89; 79 was deleted), Epic 18 = 90 (91–92), Epic 19 = 93 (94–98).
- **CLI:** `az devops login` and paste the PAT (Work Items: Read & write) at the hidden prompt — never in chat, and revoke it when done. Set the defaults with `az devops configure --defaults organization=… project=…`. In WIQL, `@project` returned no results; use the literal project name. Link a story to its epic with `az boards work-item relation add --relation-type parent`.
- **Keep the docs in sync:** any change to these Boards items must also be made in `docs/requirements/user-stories.md`, whose IDs match one-to-one.

---

## Instructions for Claude Code

- Read `docs/requirements/user-stories.md` in full before implementing any epic — acceptance criteria there are the actual spec, this file is orientation only.
- Follow the modular multi-tier structure above; keep `RAW.Domain` free of external dependencies.
- Every AI-generated output (category mapping, extracted fields, draft narrative, score) must be persisted alongside any human edit/override and the stated reason — never overwrite in place.
- Audit entries are append-only; do not design any update/delete path for audit records.
- Residual risk scoring must be mathematically incapable of reaching zero — validate this in both the calculation and the configuration-save path.
- Commit incrementally per logical unit of work (one epic/story at a time where practical) with descriptive messages — commit history is graded evidence.
- Log prompts/agent instructions used for generation into `/ai` as you go — this is a repo deliverable, not optional documentation.
