# Dev DB backup (2026-10-08)

Synthetic data snapshot of `risk_governance_db` from the dev environment.

- `risk_governance_db.dump` — `pg_dump` custom format (restore with `pg_restore`)
- `risk_governance_db.sql` — plain SQL (restore with `psql`)

Restore into a fresh local database (Docker Postgres is on port 5433):

```powershell
$env:PGPASSWORD="postgres"
psql -h localhost -p 5433 -U postgres -c "CREATE DATABASE risk_governance_db;"
pg_restore -h localhost -p 5433 -U postgres -d risk_governance_db --no-owner --no-privileges ops/db-backup/risk_governance_db.dump
```

Attachment blobs are not in the repo. They go in the `change-request-attachments` container.
