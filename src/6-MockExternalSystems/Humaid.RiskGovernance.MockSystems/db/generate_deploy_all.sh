#!/usr/bin/env bash
# Regenerates deploy_all.sql by concatenating schema.sql, functions/, and seed.sql in apply order.
# Mirrors src/4-Persistence/Humaid.RiskGovernance.AdminUI.DB/generate_deploy_all.sh exactly - run
# this after adding/editing anything under functions/ or either .sql file. deploy_all.sql is a
# generated convenience artifact, not a second source of truth - edit the source files, then
# re-run this; never hand-edit deploy_all.sql directly.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

OUT="deploy_all.sql"

{
  echo "-- =================================================================================="
  echo "-- deploy_all.sql - GENERATED FILE. Do not edit directly."
  echo "-- Regenerate with ./generate_deploy_all.sh after changing schema.sql, functions/, or seed.sql."
  echo "--"
  echo "-- One-shot setup for Humaid.RiskGovernance.MockSystems: creates the 'mock_systems' schema,"
  echo "-- its 3 tables, every stored function the service calls, and seeds synthetic dev data -"
  echo "-- against the SAME Postgres instance/database the Workbench uses (different schema, not a"
  echo "-- separate database - see README.md). Run once. Not idempotent by design, same as the"
  echo "-- Workbench's own deploy_all.sql."
  echo "--"
  echo "-- Usage (against the same Docker Postgres the Workbench already uses):"
  echo "--   psql -U postgres -h localhost -p 5433 -d risk_governance_db -v ON_ERROR_STOP=1 -f deploy_all.sql"
  echo "-- =================================================================================="
  echo
  echo "BEGIN;"
  echo

  echo "-- ============================== schema =============================================="
  echo
  echo "-- ---- schema.sql ----"
  cat schema.sql

  echo
  echo "-- ============================== functions ============================================"
  while IFS= read -r f; do
    echo
    echo "-- ---- $f ----"
    cat "$f"
  done < <(find functions -name '*.sql' | sort)

  echo
  echo "-- ============================== seed =================================================="
  echo
  echo "-- ---- seed.sql ----"
  cat seed.sql

  echo
  echo "COMMIT;"
} > "$OUT"

echo "Wrote $OUT ($(wc -l < "$OUT") lines)"
