-- Risk Assessment Workbench schema.
-- Apply in numeric order: schema/*.sql, then functions/**/*.sql, then seed/*.sql.
-- See ../README.md for the exact psql invocation.

-- gen_random_uuid() is a Postgres core builtin since PG13 - no extension needed (and Azure
-- Database for PostgreSQL Flexible Server doesn't allow-list pgcrypto by default, so trying to
-- CREATE EXTENSION it there fails outright). Deliberately no CREATE EXTENSION line here.

-- Conventions used throughout this schema:
--  * Every table has a UUID primary key (gen_random_uuid()).
--  * Enumerated columns are TEXT + CHECK, not native Postgres ENUM - adding an allowed value
--    later is an ALTER TABLE, not an ALTER TYPE against every dependent object/function.
--  * "Who did this" is always either an app_user id, or NULL with actor_label = 'system/AI' for
--    anything the platform itself produced (an AI call or a deterministic calculation).
--  * Nothing is ever hard-deleted or overwritten without a corresponding audit_event row - see
--    013_audit.sql and docs/architecture/architecture-mapping.md.
