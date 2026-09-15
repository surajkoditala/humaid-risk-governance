# Ops

## Local dev — one command

```bash
bash ops/setup-local-db.sh
```

Starts Docker Postgres + Azurite (`docker-compose.yml`), creates `risk_governance_db`, and applies
**both** services' `deploy_all.sql` (Workbench: `src/4-Persistence/Humaid.RiskGovernance.AdminUI.DB/`;
Mock Systems: `src/6-MockExternalSystems/Humaid.RiskGovernance.MockSystems/db/`) — same database,
different schema, because Mock Systems is deliberately not part of the monolith. Safe to re-run:
skips straight to "already set up" if the database exists, rather than failing partway through
non-idempotent `CREATE TABLE` statements. `--reset` drops and recreates from scratch (destroys
local data — only runs with the flag, never implicitly).

After that, `dotnet run` both services plus `npm run dev` for the webapp — see the root `README.md`
for exact commands.

The rest of this file is the **target deployment shape** agreed on the 2026-09-09 architecture sync
(`Genius hacks - Q3 sync up.vtt`), written so the actual Terraform/Bicep pipeline has a spec to
build against. **No IaC files live here yet** — provisioning Azure resources and the deploy
pipeline is DevOps' explicit ownership (CLAUDE.md's team table), not written as part of this pass.

## Target Azure resources

| Resource | Purpose | Notes from the sync |
|---|---|---|
| Container Apps environment + 2 Container Apps | Workbench (`1-API`, the monolith) and Mock Systems (`6-MockExternalSystems`) - two separate apps, not one, per Suleman's "It shouldn't be part of the monolith" agreement | "Let's do container apps, it's the cheapest" |
| Azure Database for PostgreSQL Flexible Server (Burstable) | Same schema `deploy_all.sql` already applies locally | One instance; Mock Systems uses its own `mock_systems` schema within it, not a separate server, for cost |
| Storage Account (Blob) | Real document uploads (Phase 3 Step 4) - Azurite is the local stand-in | `BLOB_STORAGE_CONNECTION_STRING` |
| Key Vault | Secrets (`ANTHROPIC_API_KEY` / `FOUNDRY_API_KEY`, Postgres credentials) - never baked into a container image | Referenced by the Container Apps, not provisioned by application code |
| Log Analytics + Application Insights | Logs/traces only, deliberately lean | Explicitly flagged on the call: a prior project's monitoring alone hit ~$500/month - "we need to save money". Code-side wiring is already in place (`Azure.Monitor.OpenTelemetry.AspNetCore`, both services' `Program.cs`) and stays fully inert until `APPLICATIONINSIGHTS_CONNECTION_STRING` is set - provisioning the actual resource (ideally on a low-volume/free-tier sampling plan) is the only remaining step. |
| Azure AI Foundry project | Hosts the model the AI clients call | **Not IaC-provisioned** - set up via the Azure Portal (Suraj's side), per the call ("the rest all services can be done through IaC... but the Foundry project itself" is portal-managed). Terraform only provisions the Container Apps that *call* it. |

## Container image build

Per the call: "the agent code, whatever you have, will be part of your application code only" -
there's no separate "agent" artifact to build. Each service has its own multi-stage `Dockerfile`
(SDK image to `dotnet publish`, `aspnet` runtime image to run) - the image is pushed to a container
registry and deployed to its Container App. The webapp (`5-Presentation`) is a static build
(`npm run build`), served from whichever static hosting the deploy pipeline targets - not part of
either container image below.

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
directly onto Container App env vars / Key Vault references) - no code change needed to move from
local dev to Azure, only where each value comes from.

**Workbench (`1-API`):**

| Variable | Local dev value | Azure |
|---|---|---|
| `AZURE_POSTGRESQL_CONNECTIONSTRING` | Docker Postgres, port 5433 | Flexible Server connection string (Key Vault) |
| `AUTH0_DOMAIN` / `AUTH0_AUDIENCE` | blank (DevBypassAuthHandler active) | real Auth0 tenant values once configured |
| `CORS_ALLOWED_ORIGINS` | `["http://localhost:3000"]` | the deployed webapp's origin |
| `AI_PROVIDER` | `Anthropic` | `AzureFoundry` once the Foundry project exists |
| `ANTHROPIC_API_KEY` / `ANTHROPIC_MODEL` | dev key, if using the Anthropic path | Key Vault reference, if still using the Anthropic path |
| `FOUNDRY_PROJECT_ENDPOINT` / `FOUNDRY_API_KEY` / `FOUNDRY_MODEL_DEPLOYMENT` | unset until the Foundry project exists | the Foundry project's own endpoint/key/deployed model name |
| `MOCK_SYSTEMS_BASE_URL` | `http://localhost:5220` | the Mock Systems Container App's internal URL |
| `BLOB_STORAGE_CONNECTION_STRING` | Azurite's well-known local emulator key (not a secret) | Storage Account connection string (Key Vault) |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | blank (telemetry registration skipped entirely) | the Application Insights resource's connection string (Key Vault) |

**Mock Systems (`6-MockExternalSystems`):**

| Variable | Local dev value | Azure |
|---|---|---|
| `MOCK_SYSTEMS_POSTGRESQL_CONNECTIONSTRING` | Docker Postgres, port 5433 | same Flexible Server, `mock_systems` schema |
| `CORS_ALLOWED_ORIGINS` | `["http://localhost:5210"]` | the Workbench Container App's internal URL - Mock Systems is only ever called by the Workbench, never the browser directly |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | blank | same Application Insights resource as the Workbench, or its own - either works, cost is the only real deciding factor |

## Open items for the actual IaC pass

- Exact Terraform module layout - not decided; this README is the spec, not the implementation.
- Whether the two Container Apps sit in the same Container Apps environment (cheaper, simpler
  internal networking) or separate ones - leaning toward same environment given the cost
  constraint raised on the call.
- Auth0 tenant setup for production (currently dev-bypass only, both frontend and backend).
