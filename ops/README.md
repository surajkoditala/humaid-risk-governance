# Ops

## Local dev — one command

```bash
bash ops/setup-local-db.sh
```

Starts Docker Postgres + Azurite (`docker-compose.yml`), creates `risk_governance_db`, and applies
**both** services' `deploy_all.sql` (Workbench: `src/4-Persistence/Humaid.RiskGovernance.AdminUI.DB/`;
Mock Systems: `src/6-MockExternalSystems/Humaid.RiskGovernance.MockSystems/db/`) — same database,
different schema, because Mock Systems is deliberately not part of the Workbench. Safe to re-run:
skips straight to "already set up" if the database exists, rather than failing partway through
non-idempotent `CREATE TABLE` statements. `--reset` drops and recreates from scratch (destroys
local data — only runs with the flag, never implicitly).

After that, `dotnet run` both services plus `npm run dev` for the webapp — see the root `README.md`
for exact commands.

The rest of this file covers how the app runs in Azure. The shape was agreed on the 2026-09-09
architecture sync (`Genius hacks - Q3 sync up.vtt`) and is now built: the Terraform lives in
`ops/iac/` (`modules/` — ten reusable modules; `environments/dev/` — the dev environment) and its
pipelines in `.azure-pipelines/iac/`. Provisioning Azure resources is DevOps' ownership.

## Azure resources (dev)

| Resource | Purpose | Notes |
|---|---|---|
| Container Apps environment + 2 Container Apps | Workbench (`1-API`, with the webapp baked in) and Mock Systems (`6-MockExternalSystems`) - two separate apps in one VNet-integrated environment (Consumption profile), per the agreement on the call that Mock Systems shouldn't be part of the Workbench | Workbench has external ingress; Mock Systems is internal-only, so only the Workbench can reach it. "Let's do container apps, it's the cheapest" |
| Azure Database for PostgreSQL Flexible Server | Same `deploy_all.sql` schema as local, database `risk_governance_db` | One server; Mock Systems uses its own `mock_systems` schema within it, for cost. In `centralus` (the subscription can't provision it in `eastus2`), private endpoint in `eastus2` |
| Storage Account (Blob) | Document uploads - Azurite is the local stand-in | Private endpoints; the apps use their managed identity (Storage Blob Data Contributor), not account keys |
| Key Vault | The two AI secrets (`ANTHROPIC-API-KEY`, `FOUNDRY-API-KEY`) - never baked into an image | Read at app startup through managed identity; each app allow-lists only its own secrets |
| Container registry | Images pushed by `workbench.yml` / `mock-api.yml` | Pulled by the user-assigned identity `id-ca-gh-dev` (AcrPull), no registry password |
| Log Analytics + Application Insights | Logs/traces, deliberately lean | A prior project's monitoring alone hit ~$500/month - "we need to save money". Resource-level diagnostic settings stay off on purpose |
| Azure Monitor alerts | Smart Detection failure anomalies + scheduled query rules (failed-request burst, unhandled exceptions), emailed via the `ag-sre-*` action group | `environments/dev/main.monitor.tf`; the SRE watchdog pipeline (`.azure-pipelines/observability/`) adds an AI-narrated GitHub issue per condition |
| Azure AI Foundry project | Hosts the model the AI clients call in Azure (`gpt-4.1-mini`) | **Not IaC-provisioned** - set up in the Azure Portal, per the call; Terraform only points the Workbench at it (`FOUNDRY_PROJECT_ENDPOINT`) |

## Container image build

Per the call: "the agent code, whatever you have, will be part of your application code only" -
there's no separate "agent" artifact to build. Each service has its own multi-stage `Dockerfile`
(SDK image to `dotnet publish`, `aspnet` runtime image to run) - the image is pushed to a container
registry and deployed to its Container App by `.azure-pipelines/workbench/workbench.yml` and
`.azure-pipelines/mock-api/mock-api.yml` (push to `release/*`). The webapp (`5-Presentation`) has no
image of its own in Azure: the Workbench Dockerfile's `webapp-build` stage runs `npm run build` and
copies the output into the API's `wwwroot`, so one container serves both. (`webapp/Dockerfile` is
only for running the frontend on its own in `docker-compose.app.yml`.)

**Build context is the repo root for both** (each project references sibling projects by relative
path, so the build stage needs the whole `src/` tree it depends on - see each Dockerfile's own
top comment):

```bash
docker build -f src/1-API/Humaid.RiskGovernance.AdminUI.Web/Dockerfile -t humaid-workbench .
docker build -f src/6-MockExternalSystems/Humaid.RiskGovernance.MockSystems/Dockerfile -t humaid-mocksystems .
```

Both listen on `:8080` inside the container (`ASPNETCORE_URLS`) - the Container Apps convention.
Config is unchanged from local dev, injected via `-e KEY=value` / Container App env vars (see the
table below) - no secret is baked into either image.

**Building behind an SSL-inspecting corporate proxy** (Netskope, Zscaler, etc.)? `dotnet restore`
inside the build stage will fail with `NU1301` / `UntrustedRoot` if so - see `ops/certs/README.md`
to fix it (drop your proxy's root CA in `ops/certs/`, gitignored, picked up automatically by both
Dockerfiles).

**Smoke-testing a built image locally** against the same `ops/docker-compose.yml` Postgres/Azurite
used for local dev (both containers need to be on that compose network to resolve each other and
Postgres by container name - the compose project's network is `ops_default` by default):

```bash
docker run -d --name mocksystems --network ops_default -p 5221:8080 \
  -e MOCK_SYSTEMS_POSTGRESQL_CONNECTIONSTRING="Host=risk-governance-postgres;Username=postgres;Password=postgres;Database=risk_governance_db;Port=5432" \
  humaid-mocksystems

docker run -d --name workbench --network ops_default -p 5211:8080 \
  -e AZURE_POSTGRESQL_CONNECTIONSTRING="Host=risk-governance-postgres;Username=postgres;Password=postgres;Database=risk_governance_db;Port=5432" \
  -e MOCK_SYSTEMS_BASE_URL="http://mocksystems:8080" \
  -e BLOB_STORAGE_CONNECTION_STRING="DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==;BlobEndpoint=http://risk-governance-azurite:10000/devstoreaccount1;" \
  humaid-workbench
```

Verified working end to end (2026-09-15): both images build clean, `curl localhost:5211/api/Ping`
and `curl localhost:5221/api/customers` both return real data, and the Workbench container reaches
the Mock Systems container over the Docker network (`GET /api/DataIngestion/MockCustomers`) exactly
as it will Container-App-to-Container-App in Azure.

## Environment variables

Every value below is read via `IConfiguration` (flat keys, screaming-snake-case, so they map
directly onto Container App env vars) - no code change needed to move from local dev to Azure, only
where each value comes from. In Azure, the env vars are set by Terraform
(`ops/iac/environments/dev/locals.tf`), and Key Vault is added as the last (highest-priority) config
source whenever `PEP_KEY_VAULT` is set. Postgres and Blob each have a password-based key for local
dev and a passwordless fallback that Azure uses (managed identity, Entra token).

**Workbench (`1-API`):**

| Variable | Local dev value | Azure |
|---|---|---|
| `AZURE_POSTGRESQL_CONNECTIONSTRING` | Docker Postgres, port 5433 | unset - `AZURE_POSTGRESQL_ENDPOINT` is used instead |
| `AZURE_POSTGRESQL_ENDPOINT` | unset | passwordless connection string (`User Id=` the app's identity), token from managed identity |
| `AUTH0_DOMAIN` / `AUTH0_AUDIENCE` | blank (DevBypassAuthHandler active) | real Auth0 tenant values once configured - read at runtime, ordinary Container App env vars (not set by Terraform today) |
| `AUTH0_CLIENT_ID` | blank | the Auth0 SPA application's Client ID. Not used by the API itself - it is served to the webapp at `/config.json` together with the two values above (see below). Public, not a secret |
| `CORS_ALLOWED_ORIGINS` | `["http://localhost:3000"]` | `CORS_ALLOWED_ORIGINS__0` = the Workbench container app's own URL |
| `AI_PROVIDER` | `Anthropic` | `AzureFoundry` |
| `ANTHROPIC_API_KEY` / `ANTHROPIC_MODEL` | dev key, if using the Anthropic path | key from Key Vault (`ANTHROPIC-API-KEY`); model set by Terraform - only used if `AI_PROVIDER` is switched back to `Anthropic` |
| `ANTHROPIC_WORKSPACE_ID` | required only if the key above is Organization-scoped rather than workspace-scoped (Anthropic 400s every call otherwise) - console.anthropic.com → Settings → Workspaces → the workspace → Overview | same |
| `FOUNDRY_PROJECT_ENDPOINT` / `FOUNDRY_API_KEY` / `FOUNDRY_MODEL_DEPLOYMENT` | unset | endpoint and model (`gpt-4.1-mini`) set by Terraform; key from Key Vault (`FOUNDRY-API-KEY`) |
| `MOCK_SYSTEMS_BASE_URL` | `http://localhost:5220` | the Mock Systems container app's internal URL |
| `BLOB_STORAGE_CONNECTION_STRING` | Azurite's well-known local emulator key (not a secret) | unset - `BLOB_STORAGE_SERVICE_URI` is used instead |
| `BLOB_STORAGE_SERVICE_URI` | unset | the Storage Account's blob endpoint, accessed with managed identity (resolves to the private endpoint) |
| `PEP_KEY_VAULT` | unset (no Key Vault config source) | the Key Vault URI |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | blank (telemetry registration skipped entirely) | the dev Application Insights connection string, set by Terraform |

**Mock Systems (`6-MockExternalSystems`):**

| Variable | Local dev value | Azure |
|---|---|---|
| `MOCK_SYSTEMS_POSTGRESQL_CONNECTIONSTRING` | Docker Postgres, port 5433 | unset - `AZURE_POSTGRESQL_ENDPOINT` is used instead |
| `AZURE_POSTGRESQL_ENDPOINT` | unset | passwordless connection string to the same server (`mock_systems` schema), token from managed identity |
| `CORS_ALLOWED_ORIGINS` | `["http://localhost:5210"]` | `CORS_ALLOWED_ORIGINS__0` set by Terraform - Mock Systems is only ever called by the Workbench, never the browser directly |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | blank | the same Application Insights resource as the Workbench |

## Frontend Auth0 config is read at runtime, from the API

The webapp is static JavaScript running in the browser, so it can't see the container's env vars
directly - and Vite inlines `VITE_*` values at image build time, which froze them into the bundle
(the first deployed images shipped with them empty and showed "Auth0 is not configured"). Instead,
the Workbench API serves `GET /config.json` (anonymous, `Cache-Control: no-store`) containing
`auth0Domain`, `auth0ClientId` and `auth0Audience`, taken from the `AUTH0_DOMAIN`,
`AUTH0_CLIENT_ID` and `AUTH0_AUDIENCE` env vars in the table above; `main.jsx` fetches it before the
first render. Changing those env vars and restarting the container app changes the webapp's Auth0
settings with **no image rebuild**, and one image works in any environment.

The webapp's `VITE_AUTH0_*` values (`webapp/.env.example`) remain only as a fallback for local dev
when the API isn't serving them. `VITE_API_BASE_URL` stays build-time on purpose: it is where the
webapp finds `/config.json`, and is `""` (same origin) in the deployed image.

## Still open

- Auth0 for the deployed app is set by hand as container app env vars (`AUTH0_DOMAIN`,
  `AUTH0_CLIENT_ID`, `AUTH0_AUDIENCE`), not by Terraform - see `docs/architecture/auth0-setup.md`.
  If Terraform ever starts managing that container app's env block, add them there or an apply
  will remove them.
