#!/usr/bin/env bash
# Regenerates deploy_all.sql by concatenating schema/, functions/, and seed/ in apply order.
# Run this after adding/editing any file under schema/, functions/, or seed/ - deploy_all.sql
# is a generated convenience artifact, not a second source of truth. Edit the modular files,
# then re-run this script; never hand-edit deploy_all.sql directly.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

OUT="deploy_all.sql"

{
  echo "-- =================================================================================="
  echo "-- deploy_all.sql - GENERATED FILE. Do not edit directly."
  echo "-- Regenerate with ./generate_deploy_all.sh after changing schema/, functions/, or seed/."
  echo "--"
  echo "-- One-shot setup: creates every table, every stored function, and seeds synthetic dev"
  echo "-- data, against an EMPTY database. Run once. Schema statements are plain CREATE TABLE"
  echo "-- (not idempotent by design - see README.md), so re-running against a non-empty"
  echo "-- database will fail on the first already-existing table. Drop and recreate the"
  echo "-- database first if you need to re-run this."
  echo "--"
  echo "-- Usage:"
  echo "--   createdb -U postgres -h localhost -p 5433 risk_governance_db"
  echo "--   psql -U postgres -h localhost -p 5433 -d risk_governance_db -v ON_ERROR_STOP=1 -f deploy_all.sql"
  echo "-- =================================================================================="
  echo
  echo "BEGIN;"
  echo

  echo "-- ============================== schema =============================================="
  for f in schema/*.sql; do
    echo
    echo "-- ---- $f ----"
    cat "$f"
  done

  echo
  echo "-- ============================== functions ============================================"
  while IFS= read -r f; do
    echo
    echo "-- ---- $f ----"
    cat "$f"
  done < <(find functions -name '*.sql' | sort)

  echo
  echo "-- ============================== seed =================================================="
  for f in seed/seed_dev_users.sql seed/seed_ffiec_framework.sql seed/seed_policy_corpus.sql seed/seed_workflow_rules.sql; do
    echo
    echo "-- ---- $f ----"
    cat "$f"
  done

  echo
  echo "COMMIT;"
} > "$OUT"

echo "Wrote $OUT ($(wc -l < "$OUT") lines)"
