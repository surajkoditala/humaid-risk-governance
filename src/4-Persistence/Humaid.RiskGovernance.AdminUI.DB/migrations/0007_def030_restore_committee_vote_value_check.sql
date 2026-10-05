-- AI review on PR #60: migration 0005's DROP CONSTRAINT loop matched every CHECK on committee_vote
-- not named like its two new ones - that also caught the table's own vote-value CHECK
-- (vote IN ('Approve','Reject','Defer','ApproveWithConditions')) and never re-added it. Already
-- applied to the shared dev database before this was caught, so 0005 itself was fixed for future
-- runs (matches by column name now, not by exclusion) but this restores the constraint on any
-- database - like that one - where it was already dropped.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'committee_vote'::regclass AND contype = 'c'
          AND (pg_get_constraintdef(oid) LIKE '%vote = ANY%' OR pg_get_constraintdef(oid) LIKE '%vote IN%')
    ) THEN
        ALTER TABLE committee_vote
            ADD CONSTRAINT committee_vote_vote_check
            CHECK (vote IN ('Approve','Reject','Defer','ApproveWithConditions'));
    END IF;
END $$;
