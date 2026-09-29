-- DEF-013: seed_controls.sql needs a conflict target to stay idempotent. Guards rather than
-- silently dedupes - the control table had no seed data before this PR, so a pre-existing
-- duplicate here would be unexpected and worth a human look, not an auto-fix.
DO $$
DECLARE
    v_dupe_groups INT;
BEGIN
    SELECT count(*) INTO v_dupe_groups
    FROM (SELECT 1 FROM control GROUP BY risk_category_id, name HAVING count(*) > 1) x;
    IF v_dupe_groups > 0 THEN
        RAISE EXCEPTION 'control has % duplicate (risk_category_id, name) group(s) - resolve manually before this migration can add the UNIQUE constraint', v_dupe_groups;
    END IF;
END $$;

ALTER TABLE control ADD CONSTRAINT control_risk_category_id_name_key UNIQUE (risk_category_id, name);
