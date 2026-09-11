# Risk Governance Admin UI

Scaffolded from the `erc-insurity-adminui` reference project's **architecture pattern only**
(5-layer Clean Architecture .NET backend + React/Vite frontend, Auth0 + PostgreSQL/Dapper). No
ERC-specific business logic, entities, or vendored UI library were carried over — this is a fresh
domain.

## How it fits together

```
Browser
  |
  v
webapp  (React + Vite dev server, port 3000)
  |
  v
Humaid.RiskGovernance.AdminUI.Web  (.NET 10 API, port 5210) ---> Azure AI Foundry / Anthropic
  |                                                              (IChatCompletionClient, AI_PROVIDER)
  |---> Azure Blob Storage / Azurite (document upload + extraction)
  |
  v                                                          Humaid.RiskGovernance.MockSystems
PostgreSQL  <-----------------------------------------------  (.NET 10 API, port 5220 — own
  (risk_governance_db + mock_systems schema)                   'mock_systems' schema; the ONLY
                                                                 thing the Workbench talks to for
                                                                 CRM/Core Banking/Vendor data)
```

- **webapp** is a pure UI: no direct database access, no business logic. Auth0 Universal Login
  gates the console (a Development-only bypass stands in until a tenant is configured); the SPA
  attaches its Auth0 access token as a Bearer header on every API call.
- **Humaid.RiskGovernance.AdminUI.Web** is a Clean Architecture solution, layered
  (`1-API` / `2-Infrastructure` / `3-Service` / `4-Persistence` / `5-Presentation`) — validates the
  Auth0 token, and talks to Postgres through a thin Dapper layer that calls stored
  procedures/functions, never ad-hoc SQL or EF Core.
- **Humaid.RiskGovernance.MockSystems** (`6-MockExternalSystems`) stands in for the CRM/Core
  Banking/Vendor Management systems a real bank would already have. Deliberately **not** part of
  the monolith — its own project, own port, own Postgres schema; the Workbench's Data Ingestion
  Layer is the only thing that calls it, and only over HTTP. See its own README.
- **webapp** (`5-Presentation`) is included in `Humaid.RiskGovernance.AdminUI.slnx` as a real,
  build-integrated project (`webapp/webapp.esproj`, the `Microsoft.VisualStudio.JavaScript.Sdk`) —
  `dotnet build` on the whole solution runs `npm run build` for it too.

## Folder guide

| Path | What it is |
|------|------------|
| `src/1-API/Humaid.RiskGovernance.AdminUI.Web/` | ASP.NET Core Web API. Auth0 JWT Bearer validation (dev-bypass while no tenant is set up), CORS for the Vite dev server, controllers. |
| `src/2-Infrastructure/Humaid.RiskGovernance.AdminUI.Infrastructure/` | Interfaces, models, `OperationResult<T>` — no implementations. |
| `src/3-Service/Humaid.RiskGovernance.AdminUI.Services/` | Business logic implementing the `2-Infrastructure` interfaces. |
| `src/3-Service/Humaid.RiskGovernance.AdminUI.AI/` | AI orchestration — `IChatCompletionClient` (Anthropic direct or Azure AI Foundry) + the three AI-touchpoint clients. See `ai/README.md`. |
| `src/4-Persistence/Humaid.RiskGovernance.AdminUI.DA/` | Dapper repos — every query calls a stored routine. |
| `src/4-Persistence/Humaid.RiskGovernance.AdminUI.DB/` | The schema's single source of truth — `schema/`, `functions/`, `seed/`, plus a generated one-shot `deploy_all.sql`. |
| `src/6-MockExternalSystems/Humaid.RiskGovernance.MockSystems/` | Mock CRM/Core Banking/Vendor Management — deliberately outside the monolith. |
| `webapp/` (`5-Presentation`) | Frontend. Single-page Vite app. `webapp.esproj` makes it a real project in the solution. |
| `evals/` | The evaluation framework — see `evals/README.md`. |
| `ai/` | AI orchestration docs, mirrored prompts, and `data-generation/` (how synthetic seed data was produced). |
| `ops/` | Local dev (`docker-compose.yml` — Postgres + Azurite) and the target Azure deployment shape (`README.md`) — no IaC files yet, that's DevOps' pass. |

## Prerequisites

- Node.js (LTS)
- .NET 10 SDK
- A local PostgreSQL instance for this project's own schema

## First-time setup

1. **Database** — one command starts Docker Postgres + Azurite and applies both services' full
   schema/functions/seed data (`deploy_all.sql`, one per service):
   ```bash
   bash ops/setup-local-db.sh
   ```
   Safe to re-run — skips setup if the database already exists rather than failing halfway
   through (`--reset` to drop and start clean). See `ops/README.md`.
2. **Backend settings** — copy `appsettings.Development.json.example` → `appsettings.Development.json`
   in both `src/1-API/Humaid.RiskGovernance.AdminUI.Web/` and
   `src/6-MockExternalSystems/Humaid.RiskGovernance.MockSystems/` (git-ignored, local-only).
   Defaults already match `ops/docker-compose.yml` — only `ANTHROPIC_API_KEY`/`ANTHROPIC_MODEL`
   need a real value to make the AI endpoints do anything.
3. **Frontend Auth0/API settings** — copy `webapp/.env.example` to `webapp/.env.local` and fill in
   your Auth0 application's domain/client ID once available. Until then the app runs in a
   "continue without signing in" local dev mode.
4. **Frontend dependencies**:
   ```powershell
   cd webapp
   npm install
   ```

## Running the app

Three processes (Mock Systems first — the Workbench calls it at intake):
```powershell
dotnet run --project src/6-MockExternalSystems/Humaid.RiskGovernance.MockSystems
```
```powershell
dotnet run --project src/1-API/Humaid.RiskGovernance.AdminUI.Web
```
```powershell
cd webapp
npm run dev
```

| URL | What |
|-----|------|
| http://localhost:3000/ | Frontend (Vite dev server) |
| http://localhost:5210/api/Ping | Workbench backend, direct |
| http://localhost:5220/api/ping | Mock Systems backend, direct |

## Current state

This is now the **Risk Assessment Workbench** (see `CLAUDE.md` and `docs/requirements/user-stories.md`
for the full brief). Backend fully wired end to end (Controller → Service → Repo → stored
function), covering all 10 epics: Change Request Intake, Category Mapping, Policy Research,
Document Extraction, AI-Drafted Narrative, Analyst Review/Override, Risk Scoring, Committee Review
& Voting, the Audit trail, and Platform Configuration. The full webapp is built too (Intake, My
Requests, Analyst Inbox, the Assessment Workspace, Committee Queue, Configuration) — not just the
API. See `docs/architecture/architecture-mapping.md` for how this maps onto CLAUDE.md's own
suggested structure, and `docs/governance/human-in-the-loop-gates.md` for where every AI output
gets a human review/override gate.

**Ecosystem expansion** (per the architect's Platform Ecosystem Diagram and the 2026-09-09
architecture sync) is also wired:
- **AI provider is swappable** (`AI_PROVIDER` = `Anthropic` or `AzureFoundry`) — no prompt/parsing
  code changes between the two; see `ai/README.md`.
- **Mock External Systems** (`src/6-MockExternalSystems/`) stand in for a bank's CRM/Core
  Banking/Vendor Management systems, deliberately outside the monolith.
- **Data Ingestion Layer** links a change request to a Mock Systems customer/product/vendor at
  intake and persists an immutable snapshot — the only thing downstream (AI, scoring, analyst UI)
  ever reads.
- **Real document extraction** — uploaded PDF/DOCX/XLSX go to blob storage (Azurite locally) and
  get their text extracted deterministically (`PdfPig`/`DocumentFormat.OpenXml`), not pasted by
  hand.
- **Feedback loop** — a committee decision pushes a go-live flag / updated risk rating / risk flag
  back to whichever Mock Systems entity the change request was linked to, itself an audited event.
- **Evaluation framework** (`evals/`) scores the three AI-touchpoint clients against fixed
  datasets — deterministic where the domain allows it, an explicitly-labeled heuristic proxy for
  narrative quality.

**Operations and Testing** (the two remaining SDLC stages) are also covered:
- **Application Insights** — both services register `Azure.Monitor.OpenTelemetry.AspNetCore`
  whenever `APPLICATIONINSIGHTS_CONNECTION_STRING` is set (blank locally by default, deliberately
  — see `ops/README.md`'s cost note). One registration point instruments every HTTP request,
  outbound call, and existing `ILogger` call already in the codebase.
- **Unit tests** (`tests/Humaid.RiskGovernance.AdminUI.UnitTests/`) — xUnit + Moq, 50 tests
  covering the invariants the rest of this README talks about (residual-risk-never-zero, the
  committee quorum resolution rule, the citation-fabrication guard, the feedback loop's
  best-effort error handling). `dotnet test tests/Humaid.RiskGovernance.AdminUI.UnitTests`.

Database schema/functions/seed data live in `src/4-Persistence/Humaid.RiskGovernance.AdminUI.DB/`
— apply via `deploy_all.sql` (one command, see that folder's README) or the modular
`schema/`/`functions/`/`seed/` files, against `ops/docker-compose.yml`'s local Postgres. AI
orchestration lives in `src/3-Service/Humaid.RiskGovernance.AdminUI.AI/` — see `ai/README.md`.

Not yet wired: Auth0 tenant configuration (endpoints are `[Authorize]`-protected, but a
Development-only bypass — `DevBypassAuthHandler` on the backend, matching `RequireAuth.jsx` on the
frontend — stands in until a real tenant exists); the Azure AI Foundry project itself (the
`IChatCompletionClient` abstraction is ready, but no Foundry project has been provisioned yet —
`AI_PROVIDER` defaults to calling Anthropic directly); and the actual Terraform/Bicep for the
target deployment shape documented in `ops/README.md` (DevOps' explicit ownership, not started).
