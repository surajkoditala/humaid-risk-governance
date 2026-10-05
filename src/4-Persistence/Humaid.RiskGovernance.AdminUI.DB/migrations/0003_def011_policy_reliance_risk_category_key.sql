-- DEF-011: the same passage relied upon for a second risk category used to hit the old
-- (assessment_id, policy_chunk_id) conflict target and silently overwrite the first category's
-- decision - risk_category_id is now part of the key (func_recordPolicyReliance.sql's ON
-- CONFLICT target matches this; see schema/007_policy_corpus.sql for a fresh deploy). Existing
-- non-null-category rows already satisfy the old, narrower 2-column uniqueness, so they trivially
-- satisfy this wider 3-column uniqueness too - no data changes needed for those.
--
-- NULLS NOT DISTINCT (AI review on PR #60): the old constraint's NULL handling meant two
-- decisions on the same chunk with no category selected (the Policy tab's "Any category" search)
-- never conflicted and could already have duplicated on this database - dedupe those first,
-- keeping the most recently decided row, the same "newest decision wins" semantics
-- func_recordPolicyReliance's own ON CONFLICT DO UPDATE already applies going forward.
DO $$
DECLARE
    v_old_conname TEXT;
    v_dupe_groups INT;
BEGIN
    SELECT conname INTO v_old_conname
    FROM pg_constraint
    WHERE conrelid = 'assessment_policy_reliance'::regclass
      AND contype = 'u'
      AND pg_get_constraintdef(oid) = 'UNIQUE (assessment_id, policy_chunk_id)';

    IF v_old_conname IS NOT NULL THEN
        EXECUTE format('ALTER TABLE assessment_policy_reliance DROP CONSTRAINT %I', v_old_conname);
    END IF;

    SELECT count(*) INTO v_dupe_groups
    FROM (
        SELECT 1 FROM assessment_policy_reliance
        WHERE risk_category_id IS NULL
        GROUP BY assessment_id, policy_chunk_id HAVING count(*) > 1
    ) x;

    IF v_dupe_groups > 0 THEN
        RAISE NOTICE 'Deduping % null-category assessment_policy_reliance group(s), keeping the most recent decision', v_dupe_groups;
        DELETE FROM assessment_policy_reliance apr
        WHERE risk_category_id IS NULL
          AND id NOT IN (
              SELECT DISTINCT ON (assessment_id, policy_chunk_id) id
              FROM assessment_policy_reliance
              WHERE risk_category_id IS NULL
              ORDER BY assessment_id, policy_chunk_id, decided_at DESC
          );
    END IF;
END $$;

ALTER TABLE assessment_policy_reliance
    ADD CONSTRAINT assessment_policy_reliance_assessment_id_risk_category_id_policy_chunk_id_key
    UNIQUE NULLS NOT DISTINCT (assessment_id, risk_category_id, policy_chunk_id);
