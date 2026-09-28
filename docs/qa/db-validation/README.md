# Manual database validation (read-only)

How the data tests were run, and how to repeat them by hand against the local Docker Postgres.
The SQL in [`db-manual-validation.sql`](db-manual-validation.sql) is exported from the evidence of the
automated run (`tests/e2e/specs/db/01-data-integrity.db.spec.ts`), so it is exactly what was executed.

## 1. Prerequisites

1. Start Docker Desktop.
2. Check the containers are up:
   ```powershell
   docker ps --format "{{.Names}}  {{.Status}}  {{.Ports}}"
   ```
   Expect `risk-governance-postgres ... 0.0.0.0:5433->5432/tcp`.
3. If it's missing, run `bash ops/setup-local-db.sh` from the repo root. This creates the database and applies
   both `deploy_all.sql` scripts. Credentials are `postgres` / `postgres`, port **5433**, database
   `risk_governance_db`. No other credentials are needed.

## 2. Open a read-only session

```powershell
docker exec -it risk-governance-postgres psql -U postgres -d risk_governance_db
```
Then, inside psql:
```sql
SET default_transaction_read_only = on;
SHOW transaction_read_only;          -- expect: on
\x auto
```
Prove the guard works (this must fail with *cannot execute UPDATE in a read-only transaction*):
```sql
UPDATE app_user SET display_name = display_name;
```

## 3. Run the checks

**Option A: one block at a time.** Open `db-manual-validation.sql`, copy one block (each starts with
`\echo 'TC-DB-0xx ...'`) and paste it into psql. Compare the result with the table below.

**Option B: the whole file at once.**
```powershell
docker cp docs/qa/db-validation/db-manual-validation.sql risk-governance-postgres:/tmp/v.sql
docker exec -it risk-governance-postgres psql -U postgres -d risk_governance_db -f /tmp/v.sql
docker exec risk-governance-postgres rm /tmp/v.sql
```
(In Git Bash, prefix the `docker` commands with `MSYS_NO_PATHCONV=1`.)

## 4. What to look for (local Docker run, 25 Sep 2026)

| Check | What it verifies | Pass condition | Local result |
|---|---|---|---|
| TC-DB-000 | Session is read-only; login privileges | `transaction_read_only = on`; ideally a login with no write grants | on ✔. The login is a superuser (advisory) |
| TC-DB-001 | All 26 tables exist (public + mock_systems) | none missing | 26 present ✔ |
| TC-DB-002 | Audit append-only trigger | `trg_block_audit_event_mutation`, `tgenabled = O`, `BEFORE DELETE OR UPDATE`, body has `RAISE EXCEPTION`; *audit mutators* query returns 0 rows | ✔ |
| TC-DB-003 | FFIEC framework seed | 1 FFIEC framework; 4 categories, each citing FFIEC and ≥ 3 sub-factors | 7 / 4 / 3 / 7 sub-factors ✔ |
| TC-DB-004 | Change-type → category map | Vendor = Customers & Entities + Delivery Channels, etc. | no gaps ✔ |
| TC-DB-005 | Seed users | 4 roles; 0 duplicate e-mails/subjects; 0 non-`@example.*` e-mails | ✔ |
| TC-DB-006 | Foreign keys | all `convalidated = true` | 42 FKs ✔ |
| TC-DB-010 | Residual > 0 and = inherent − effectiveness × factor | `nonpositive`, `mf_ge_1`, `formula_mismatch` all 0 | n/a (0 scores locally) |
| TC-DB-011 | Overrides keep a reason, analyst attribution, original value | every column 0 | ✔ (0 overrides) |
| TC-DB-012 | One active scoring config per category, < 1.0, with a reason | `active = 1`, `active_mf < 1`, `no_reason = 0` | 0.850 × 4 ✔ |
| TC-DB-013 | Assessments pinned to their config version | `unpinned = 0` | **24 of 24 unpinned ✘ (DEF-016)** |
| TC-DB-014 | Status consistency request ↔ assessment ↔ decision | every column 0 | ✔ |
| TC-DB-015 | Finalized assessments passed the review gates | 0 rows with `cats = 0`, AI-drafted, unscored or no policy | **12 of 12 finalized with 0 categories ✘ (DEF-001)** |
| TC-DB-016 | Votes by committee members only; conditions/rationale present; quorum | every column 0 | ✔ (5 votes) |
| TC-DB-017 | Attachment versions / extension vs type / extracted text | max version > 1; mismatches 0 | n/a (0 attachments locally) |
| TC-DB-018 | Request content quality and numbering | blanks, overlong, malformed, gaps = 0 | ✔ |
| TC-DB-019 | Reliance unique key includes the category | key contains `risk_category_id` | **`UNIQUE (assessment_id, policy_chunk_id)` ✘ (DEF-011)** |
| TC-DB-020 | Audit: humans named, changes have reasons, no future timestamps | every column 0 | 57 events ✔ |
| TC-DB-021 | Every domain record has an audit event | `missing = 0` for every entity | ✔ |
| TC-DB-022 | No silently overwritten votes | 0 rows | ✔ |
| TC-DB-030 | Snapshots point at real mock-system records | dangling = 0 | ✔ (0 snapshots) |
| TC-DB-031 | Decisions written back to the mock systems | 0 rows not written back | ✔ (0 decisions) |
| TC-DB-032 | No real-looking PII (SSN, card, IBAN, real e-mail) | 0 rows | ✔ |
| TC-DB-033 | Controls and policy passages per category | ≥ 1 control and ≥ 3 passages per category | **0 controls, 1–2 passages ✘ (DEF-013 / DEF-032)** |
| TC-DB-034 | One active workflow rule per key, valid quorum | `active = 1`; quorum > 0 | `{"quorum": 2}` ✔ |
| TC-DB-035 | QA test-data footprint | informational | 0 QA rows locally |

## 5. Optional: prove the audit trigger blocks writes

This deliberately attempts a write, so run it in a **separate session without** the read-only setting.
The trigger must reject it, and the `ROLLBACK` guarantees nothing changes either way:
```sql
BEGIN;
UPDATE audit_event SET reason = 'tamper test' WHERE id = (SELECT id FROM audit_event LIMIT 1);
-- expect: ERROR:  audit_event is append-only: UPDATE is not permitted
ROLLBACK;
```

## 6. Re-run the automated version

```powershell
cd tests/e2e
$env:DB_URL = "postgres://postgres:postgres@localhost:5433/risk_governance_db"
npx playwright test --project=db
node scripts/export-db-sql.mjs      # regenerates db-manual-validation.sql from the new evidence
```
Evidence for every query (SQL, row count, rows) is in `tests/e2e/evidence/db/`.
