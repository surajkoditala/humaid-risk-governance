# Humaid.RiskGovernance.AdminUI.DB

Plain SQL — not a compiled project. This is the schema's single source of truth: every repo
method in `4-Persistence/Humaid.RiskGovernance.AdminUI.DA` calls a named function from here via
Dapper; nothing issues ad-hoc SQL. See `docs/architecture/architecture-mapping.md` for why this is
a folder of scripts rather than an EF Core migration project.

## Apply against local Postgres — one shot

`deploy_all.sql` is every schema, function, and seed file concatenated in apply order, wrapped in
a single transaction. It's generated (`./generate_deploy_all.sh`) from the modular files below —
edit those, never `deploy_all.sql` directly, then regenerate.

```powershell
$env:PGPASSWORD = "postgres"
createdb -U postgres -h localhost -p 5433 risk_governance_db
psql -U postgres -h localhost -p 5433 -d risk_governance_db -v ON_ERROR_STOP=1 -f deploy_all.sql
```

That's it — 22 tables, ~81 functions, and the synthetic seed data (dev users, FFIEC framework,
policy corpus, workflow rules) all exist after this one command. Because it's plain `CREATE TABLE`
(not idempotent — see below), this only runs cleanly against an *empty* database; drop and
recreate first if you need to re-run it.

## Apply against local Postgres — modular (for incremental changes)

Two supported local options - both are "local Postgres", neither needs a hosted/cloud DB or any
corporate sign-in:

**Option A - Docker (recommended, matches `ops/docker-compose.yml`):**

```powershell
docker compose -f ..\..\..\ops\docker-compose.yml up -d
# Postgres is now on localhost:5433 (5433, not 5432 - see the compose file's comment on why)
```

**Option B - a native Postgres install already running on this machine** (e.g. port 5432) - just
point the commands below at that port/host instead.

Then, against whichever instance (adjust `-p`/host as needed):

```powershell
$env:PGPASSWORD = "postgres"   # or your native instance's password
$db = "risk_governance_db"
$port = 5433                   # 5433 for the Docker option above, 5432 for a native install

psql -U postgres -h localhost -p $port -tc "SELECT 1 FROM pg_database WHERE datname='$db'" | Select-String "1" `
    -Quiet -ErrorAction SilentlyContinue | Out-Null
if (-not $?) { & createdb -U postgres -h localhost -p $port $db }

Get-ChildItem schema\*.sql | Sort-Object Name | ForEach-Object { psql -U postgres -h localhost -p $port -d $db -v ON_ERROR_STOP=1 -f $_.FullName }
Get-ChildItem functions -Recurse -Filter *.sql | Sort-Object FullName | ForEach-Object { psql -U postgres -h localhost -p $port -d $db -v ON_ERROR_STOP=1 -f $_.FullName }
Get-ChildItem seed\*.sql | Sort-Object Name | ForEach-Object { psql -U postgres -h localhost -p $port -d $db -v ON_ERROR_STOP=1 -f $_.FullName }
```

(bash equivalent: `for f in schema/*.sql; do psql -U postgres -d risk_governance_db -f "$f"; done`, then the same for `functions/**/*.sql` and `seed/*.sql`, seed files last and in the order `seed_dev_users.sql` → `seed_ffiec_framework.sql` → `seed_policy_corpus.sql` since later seeds reference earlier ones.)

Then point `src/1-API/Humaid.RiskGovernance.AdminUI.Web/appsettings.Development.json`'s
`AZURE_POSTGRESQL_CONNECTIONSTRING` at `risk_governance_db`.

## Verify

```sql
\dt                                   -- every table below should be listed
\df func_*                            -- every stored function should be listed
SELECT * FROM audit_event LIMIT 1;    -- then try UPDATE/DELETE on it - both must fail
```

## Layout

- `schema/` — tables, in dependency order (`001`..`013`). Every enumerated column is `TEXT` +
  `CHECK`, not a native Postgres `ENUM` — see `schema/001_extensions_and_conventions.sql`.
- `functions/` — one folder per module, one file per stored function. Every function that writes
  an AI-generated or human-editable value also writes an `audit_event` row in the same transaction
  (Postgres functions are already atomic per call — no explicit `BEGIN/COMMIT` needed).
- `seed/` — synthetic data only: dev users, the FFIEC framework/categories, a short policy corpus.
  Run once against an empty database, in the order listed above.
- `deploy_all.sql` — generated single-file concatenation of all three, for a one-command setup.
  Source of truth is still `schema/`, `functions/`, `seed/`; regenerate with
  `./generate_deploy_all.sh` after editing any of them.

## Epics covered

Fully wired (schema + functions, matched by `.NET` `Controller → Service → Repo`): every epic -
Epic 1 (Intake), Epic 2 (Category Mapping), Epic 3 (Policy Research), Epic 4 (Document
Extraction), Epic 5 (Narrative), Epic 7 (Scoring), Epic 8 (Committee — `011_committee.sql`),
Epic 9 (Audit), Epic 10 (both halves - scoring-config in `010_scoring.sql`, workflow-rule in
`012_configuration.sql`). See `../../../docs/architecture/architecture-mapping.md`.
