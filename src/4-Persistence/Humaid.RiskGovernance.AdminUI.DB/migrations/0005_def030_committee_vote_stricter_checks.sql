-- DEF-030: the original CHECK used IS NOT NULL, which let a blank/whitespace-only string through.
--
-- First run against the real shared dev database found 4 pre-existing 'Defer' votes with blank
-- rationale - QA's own repro of this exact bug (TC-API-083), each already rolled up into a
-- resolved committee_decision. Deleting them would orphan that decision from the vote it came
-- from; backfilling a rationale nobody gave would fabricate history - both break the audit trail
-- this project exists to keep honest. Added NOT VALID instead: enforced on every new/updated row
-- from here on (DEF-030's actual goal), existing rows grandfathered in as-is rather than forced to
-- satisfy a rule that didn't exist when they were written.
DO $$
DECLARE
    v_bad_rows INT;
BEGIN
    SELECT count(*) INTO v_bad_rows FROM committee_vote
    WHERE (vote = 'ApproveWithConditions' AND (conditions_text IS NULL OR length(trim(conditions_text)) = 0))
       OR (vote IN ('Reject','Defer') AND (rationale IS NULL OR length(trim(rationale)) = 0));
    IF v_bad_rows > 0 THEN
        RAISE NOTICE '% pre-existing committee_vote row(s) predate this check and are grandfathered in, not modified', v_bad_rows;
    END IF;
END $$;

-- Drop both original CHECK constraints (whatever Postgres auto-named them) and replace with the
-- named, stricter pair - matches schema/011_committee.sql for a fresh deploy.
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT conname FROM pg_constraint
        WHERE conrelid = 'committee_vote'::regclass AND contype = 'c'
          AND conname NOT IN ('committee_vote_conditions_required', 'committee_vote_rationale_required')
    LOOP
        EXECUTE format('ALTER TABLE committee_vote DROP CONSTRAINT %I', r.conname);
    END LOOP;
END $$;

ALTER TABLE committee_vote
    ADD CONSTRAINT committee_vote_conditions_required
    CHECK (vote <> 'ApproveWithConditions' OR (conditions_text IS NOT NULL AND length(trim(conditions_text)) > 0))
    NOT VALID;
ALTER TABLE committee_vote
    ADD CONSTRAINT committee_vote_rationale_required
    CHECK (vote NOT IN ('Reject','Defer') OR (rationale IS NOT NULL AND length(trim(rationale)) > 0))
    NOT VALID;
