## Project context
The PR changes the "Mock External Systems" service (src/6-MockExternalSystems/Humaid.RiskGovernance.MockSystems): an ASP.NET Core (.NET 10) minimal API using Dapper/Npgsql over PostgreSQL that stands in for a bank's CRM, Core Banking product catalog and Vendor Management registry. It belongs to a hackathon project ("Risk Assessment Workbench") for financial-crime risk assessments. Its only consumer is the Workbench's Data Ingestion layer, over HTTP.

Read src/6-MockExternalSystems/Humaid.RiskGovernance.MockSystems/README.md and CLAUDE.md at the repo root first. The rules most likely to be violated in a diff:
- Synthetic data only: seed data and code must never contain real customer/vendor names, real account or ID numbers, or anything that looks like real PII or a real credential.
- The service is deliberately NOT part of the Workbench monolith: no ProjectReference to any 1-API..5-Presentation project, no shared DB connection/DbContext. It owns its own `mock_systems` schema and connection string.
- Persistence convention: every query in Program.cs calls a named SQL function under db/functions/ -- no ad-hoc SQL and no string-built SQL anywhere. Flag any raw SQL or string concatenation/interpolation into a query.
- db/deploy_all.sql is generated from schema.sql, functions/ and seed.sql; hand edits to it are wrong.
- Update endpoints (the inbound feedback loop) return the updated row's id or no rows, which Program.cs maps to 404.
- No secrets, keys or connection strings in code; configuration comes from environment variables. appsettings.Development.json must not be committed.

## Focus, in priority order
Correctness bugs and unhandled edge cases (including SQL function logic -- wrong joins/filters, missing NULL handling, functions whose signature no longer matches the Dapper call in Program.cs); security (injection, missing input validation on the update endpoints, secret leakage, sensitive data in logs); violations of the rules above; data-integrity/concurrency/async problems; error handling; then missing tests for new logic.
