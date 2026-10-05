# Humaid.RiskGovernance.MockSystems

Stand-in for the three systems a real bank would already have (per the architect's Platform
Ecosystem Diagram and the 2026-09-09 architecture sync): a CRM, a Core Banking product catalog, and
a Vendor Management registry. **Deliberately not part of the Workbench** — Suleman agreed
on the architecture call that this must live outside it. The Workbench's Data Ingestion Layer (`src/3-Service/.../DataIngestion`) is the only
thing allowed to read this service, and only over HTTP — nothing shares a database connection into
`mock_systems` directly.

## Run locally

Uses the same Docker Postgres instance as the Workbench (`ops/docker-compose.yml`, port 5433), but
its own schema. One command applies everything (schema + functions + seed, in order, in a
transaction) — same `deploy_all.sql` convention as
`Humaid.RiskGovernance.AdminUI.DB` (regenerate with `db/generate_deploy_all.sh` after editing
`db/schema.sql`, `db/functions/`, or `db/seed.sql` — never hand-edit `deploy_all.sql` itself):

```powershell
$env:PGPASSWORD = "postgres"
psql -U postgres -h localhost -p 5433 -d risk_governance_db -v ON_ERROR_STOP=1 -f db/deploy_all.sql
dotnet run --project src/6-MockExternalSystems/Humaid.RiskGovernance.MockSystems
```

(Or apply `db/schema.sql`, `db/functions/**/*.sql`, then `db/seed.sql` individually if you're
adding to an already-partially-applied database.)

Listens on `http://localhost:5220` (vs. the Workbench's `5210`).

## Persistence convention

Every query in `Program.cs` calls a named SQL function under `db/functions/` — no ad-hoc SQL
anywhere, the same rule the Workbench's own DB layer follows
(`docs/architecture/architecture-mapping.md`). One function per operation: `func_list*`,
`func_get*ById`, `func_update*` (the inbound side of the feedback loop — returns the updated row's
id, or no rows, so `Program.cs` can map that straight to 404).

## Endpoints

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/api/customers`, `/api/products`, `/api/vendors` | List (Intake's lookup dropdowns) |
| `GET` | `/api/customers/{id}`, `/api/products/{id}`, `/api/vendors/{id}` | Single record (Data Ingestion Layer) |
| `POST` | `/api/customers/{id}/risk-flag` | Inbound side of the feedback loop — a committee decision's customer/segment risk flag |
| `POST` | `/api/products/{id}/risk-flag` | Inbound side of the feedback loop — go-live flag + risk rating |
| `POST` | `/api/vendors/{id}/risk-flag` | Inbound side of the feedback loop — updated vendor risk rating |

## Seed data

`db/seed.sql` — one hand-authored "golden path" customer/product/vendor triplet (id prefix `...001`
in each table — the same story: a cross-border wire product for a Bangladesh corporate customer,
vetted by a certified KYC vendor) for a reliable demo lifecycle, plus additional variety including
two deliberate edge cases the architect's doc calls for: a customer/product pairing with no clean
FFIEC category mapping (`...002` in `crm_customer`/`core_banking_product` — a domestic retail
customer and a UI-only process change), and a vendor missing certification (`...002` in
`vendor_registry`). See `ai/data-generation/README.md` for how this was assembled.
