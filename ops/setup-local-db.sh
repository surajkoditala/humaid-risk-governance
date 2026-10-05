#!/usr/bin/env bash
# One command for a fresh clone: starts local Postgres + Azurite (Docker), creates the database,
# and applies BOTH services' deploy_all.sql (Workbench + Mock Systems - two separate generated
# scripts, same database, different schema, because Mock Systems is deliberately not part of the
# Workbench - see docs/architecture/architecture-mapping.md). After this, both
# `dotnet run --project src/1-API/Humaid.RiskGovernance.AdminUI.Web` and
# `dotnet run --project src/6-MockExternalSystems/Humaid.RiskGovernance.MockSystems` have
# everything they need.
#
# Safe to re-run: if the database already exists, this does nothing and tells you so, rather than
# failing halfway through non-idempotent CREATE TABLE statements. Use --reset to drop and recreate
# from scratch (destroys all local data - never runs without the flag).

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

HOST="localhost"
PORT="5433"
DB="risk_governance_db"
export PGPASSWORD="postgres"

RESET=false
if [[ "${1:-}" == "--reset" ]]; then RESET=true; fi

echo "==> Starting Docker Postgres + Azurite (ops/docker-compose.yml)..."
docker compose -f ops/docker-compose.yml up -d

echo "==> Waiting for Postgres to be healthy..."
for i in $(seq 1 30); do
  if docker exec risk-governance-postgres pg_isready -U postgres -d risk_governance_db > /dev/null 2>&1; then
    break
  fi
  sleep 2
done

DB_EXISTS=$(psql -U postgres -h "$HOST" -p "$PORT" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$DB'")

if [[ "$RESET" == true ]]; then
  echo "==> --reset passed: dropping $DB if it exists..."
  psql -U postgres -h "$HOST" -p "$PORT" -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='$DB' AND pid <> pg_backend_pid();" > /dev/null
  psql -U postgres -h "$HOST" -p "$PORT" -d postgres -c "DROP DATABASE IF EXISTS $DB;" > /dev/null
  DB_EXISTS=""
fi

if [[ -n "$DB_EXISTS" ]]; then
  echo "==> $DB already exists - skipping schema setup (deploy_all.sql is not idempotent by"
  echo "    design). Re-run with --reset if you want a clean slate, or apply new"
  echo "    schema/functions/seed files individually as you add them."
else
  echo "==> Creating $DB..."
  psql -U postgres -h "$HOST" -p "$PORT" -d postgres -c "CREATE DATABASE $DB;" > /dev/null

  echo "==> Applying Workbench schema + functions + seed (deploy_all.sql)..."
  psql -U postgres -h "$HOST" -p "$PORT" -d "$DB" -v ON_ERROR_STOP=1 \
    -f src/4-Persistence/Humaid.RiskGovernance.AdminUI.DB/deploy_all.sql

  echo "==> Applying Mock Systems schema + functions + seed (deploy_all.sql)..."
  psql -U postgres -h "$HOST" -p "$PORT" -d "$DB" -v ON_ERROR_STOP=1 \
    -f src/6-MockExternalSystems/Humaid.RiskGovernance.MockSystems/db/deploy_all.sql

  echo "==> Done. $DB is ready with both services' tables, functions, and seed data."
fi

echo
echo "Next:"
echo "  cp src/1-API/Humaid.RiskGovernance.AdminUI.Web/appsettings.Development.json.example src/1-API/Humaid.RiskGovernance.AdminUI.Web/appsettings.Development.json"
echo "  cp src/6-MockExternalSystems/Humaid.RiskGovernance.MockSystems/appsettings.Development.json.example src/6-MockExternalSystems/Humaid.RiskGovernance.MockSystems/appsettings.Development.json"
echo "  dotnet run --project src/6-MockExternalSystems/Humaid.RiskGovernance.MockSystems   (port 5220)"
echo "  dotnet run --project src/1-API/Humaid.RiskGovernance.AdminUI.Web                    (port 5210)"
echo "  cd webapp && npm install && npm run dev                                             (port 3000)"
