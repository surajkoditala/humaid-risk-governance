#!/usr/bin/env bash
# One command for a fresh clone: starts local Postgres + Azurite (Docker), creates the database,
# and applies BOTH services' deploy_all.sql (Workbench + Mock Systems - two separate generated
# scripts, same database, different schema, because Mock Systems is deliberately not part of the
# Workbench - see docs/architecture/architecture-mapping.md). After this, both
# `dotnet run --project src/1-API/Humaid.RiskGovernance.AdminUI.Web` and
# `dotnet run --project src/6-MockExternalSystems/Humaid.RiskGovernance.MockSystems` have
# everything they need.
#
# Safe to re-run. Each service's script is applied only if that service's schema is missing -
# checked by looking for a table each one creates (public.change_request for the Workbench,
# mock_systems.crm_customer for Mock Systems), NOT by whether the database itself exists: the
# Postgres Docker image auto-creates $POSTGRES_DB on first start, so "database exists" is true
# even when it is completely empty. deploy_all.sql is not idempotent by design, which is why it
# is never applied to a schema that is already there. Use --reset to drop and recreate the
# database from scratch (destroys all local data - never runs without the flag).
#
# Usage:
#   bash ops/setup-local-db.sh                 # Docker Postgres from ops/docker-compose.yml
#   bash ops/setup-local-db.sh --reset         # ...dropping and recreating the database first
#   bash ops/setup-local-db.sh --no-docker     # target a Postgres you already run (see below)
#
# Connection settings are the standard libpq variables. The defaults match ops/docker-compose.yml
# (localhost:5433, postgres/postgres). To target a different Postgres, e.g. a native install,
# set them and skip Docker - the password is yours to supply, this script never guesses one:
#   PGPORT=5432 PGPASSWORD='<your password>' bash ops/setup-local-db.sh --no-docker
# (or keep the password out of your shell history with a ~/.pgpass / %APPDATA%\postgresql\pgpass.conf
# entry). Set DB_NAME to use a database name other than risk_governance_db.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

RESET=false
USE_DOCKER=true
for arg in "$@"; do
  case "$arg" in
    --reset) RESET=true ;;
    --no-docker) USE_DOCKER=false ;;
    -h|--help) sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg (try --help)" >&2; exit 1 ;;
  esac
done

export PGHOST="${PGHOST:-localhost}"
export PGPORT="${PGPORT:-5433}"
export PGUSER="${PGUSER:-postgres}"
# Only the Docker container's own well-known password is defaulted; for any other Postgres the
# caller has to provide credentials.
if [[ "$USE_DOCKER" == true ]]; then export PGPASSWORD="${PGPASSWORD:-postgres}"; fi
DB="${DB_NAME:-risk_governance_db}"

WORKBENCH_SQL="src/4-Persistence/Humaid.RiskGovernance.AdminUI.DB/deploy_all.sql"
MOCK_SQL="src/6-MockExternalSystems/Humaid.RiskGovernance.MockSystems/db/deploy_all.sql"

# -w: never prompt for a password (fail with a clear error instead of hanging a non-interactive run).
psql_admin() { psql -w -d postgres "$@"; }
psql_db()    { psql -w -d "$DB" "$@"; }

if [[ "$USE_DOCKER" == true ]]; then
  echo "==> Starting Docker Postgres + Azurite (ops/docker-compose.yml)..."
  docker compose -f ops/docker-compose.yml up -d

  echo "==> Waiting for Postgres to be healthy..."
  for i in $(seq 1 30); do
    if docker exec risk-governance-postgres pg_isready -U postgres -d risk_governance_db > /dev/null 2>&1; then
      break
    fi
    sleep 2
  done
fi

if ! CONNECT_ERR=$(psql_admin -tAc "SELECT 1" 2>&1 >/dev/null); then
  echo "ERROR: cannot connect to Postgres at $PGHOST:$PGPORT as $PGUSER:" >&2
  echo "$CONNECT_ERR" >&2
  if [[ "$USE_DOCKER" == false ]]; then
    echo "Set PGPORT / PGUSER / PGPASSWORD for the Postgres you want to target." >&2
  fi
  exit 1
fi

if [[ "$RESET" == true ]]; then
  echo "==> --reset passed: dropping $DB if it exists..."
  psql_admin -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='$DB' AND pid <> pg_backend_pid();" > /dev/null
  psql_admin -c "DROP DATABASE IF EXISTS $DB;" > /dev/null
fi

if [[ -z "$(psql_admin -tAc "SELECT 1 FROM pg_database WHERE datname='$DB'")" ]]; then
  echo "==> Creating $DB..."
  psql_admin -c "CREATE DATABASE $DB;" > /dev/null
fi

table_exists() { [[ "$(psql_db -tAc "SELECT to_regclass('$1') IS NOT NULL")" == "t" ]]; }

APPLIED=false

if table_exists public.change_request; then
  echo "==> Workbench schema already present in $DB - skipping (deploy_all.sql is not idempotent)."
else
  echo "==> Applying Workbench schema + functions + seed (deploy_all.sql)..."
  psql_db -v ON_ERROR_STOP=1 -f "$WORKBENCH_SQL"
  APPLIED=true
fi

if table_exists mock_systems.crm_customer; then
  echo "==> Mock Systems schema already present in $DB - skipping (deploy_all.sql is not idempotent)."
else
  echo "==> Applying Mock Systems schema + functions + seed (deploy_all.sql)..."
  psql_db -v ON_ERROR_STOP=1 -f "$MOCK_SQL"
  APPLIED=true
fi

if [[ "$APPLIED" == true ]]; then
  echo "==> Done. $DB is ready with both services' tables, functions, and seed data."
else
  echo "==> Nothing to do - $DB already has both schemas. Re-run with --reset for a clean slate, or"
  echo "    apply new schema/functions/seed files individually as you add them."
fi

echo
echo "Next:"
echo "  cp src/1-API/Humaid.RiskGovernance.AdminUI.Web/appsettings.Development.json.example src/1-API/Humaid.RiskGovernance.AdminUI.Web/appsettings.Development.json"
echo "  cp src/6-MockExternalSystems/Humaid.RiskGovernance.MockSystems/appsettings.Development.json.example src/6-MockExternalSystems/Humaid.RiskGovernance.MockSystems/appsettings.Development.json"
echo "  dotnet run --project src/6-MockExternalSystems/Humaid.RiskGovernance.MockSystems   (port 5220)"
echo "  dotnet run --project src/1-API/Humaid.RiskGovernance.AdminUI.Web                    (port 5210)"
echo "  cd webapp && npm install && npm run dev                                             (port 3000)"
