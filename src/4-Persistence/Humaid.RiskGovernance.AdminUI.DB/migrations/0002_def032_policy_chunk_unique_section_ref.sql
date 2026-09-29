-- DEF-032: seed_policy_corpus.sql had no conflict target, so re-running it (harmless for every
-- other seed file) silently duplicated passages 2-3x instead of adding coverage. Dedupe first -
-- an already-provisioned database may carry real duplicates today - then enforce the constraint
-- seed_policy_corpus.sql's own ON CONFLICT now targets.
DO $$
DECLARE
    v_dupe_groups INT;
BEGIN
    SELECT count(*) INTO v_dupe_groups
    FROM (SELECT 1 FROM policy_chunk GROUP BY policy_document_id, section_ref HAVING count(*) > 1) x;

    IF v_dupe_groups = 0 THEN
        RETURN;
    END IF;

    RAISE NOTICE 'Deduping % policy_chunk group(s) with a repeated (policy_document_id, section_ref)', v_dupe_groups;

    -- Repoint any analyst reliance decision from a duplicate chunk (about to be removed) onto the
    -- surviving (lowest id) chunk in its group, unless that assessment/category already has a
    -- decision recorded against the surviving chunk - in which case that decision stands and the
    -- duplicate's is simply dropped, never silently merged.
    WITH ranked AS (
        SELECT id, policy_document_id, section_ref,
               first_value(id) OVER (PARTITION BY policy_document_id, section_ref ORDER BY id) AS keep_id
        FROM policy_chunk
    )
    UPDATE assessment_policy_reliance apr
    SET policy_chunk_id = r.keep_id
    FROM ranked r
    WHERE apr.policy_chunk_id = r.id
      AND r.id <> r.keep_id
      AND NOT EXISTS (
          SELECT 1 FROM assessment_policy_reliance apr2
          WHERE apr2.assessment_id = apr.assessment_id
            AND apr2.policy_chunk_id = r.keep_id
            AND apr2.id <> apr.id
      );

    WITH ranked AS (
        SELECT id, policy_document_id, section_ref,
               first_value(id) OVER (PARTITION BY policy_document_id, section_ref ORDER BY id) AS keep_id
        FROM policy_chunk
    )
    DELETE FROM assessment_policy_reliance apr
    USING ranked r
    WHERE apr.policy_chunk_id = r.id AND r.id <> r.keep_id;

    WITH ranked AS (
        SELECT id, policy_document_id, section_ref,
               first_value(id) OVER (PARTITION BY policy_document_id, section_ref ORDER BY id) AS keep_id
        FROM policy_chunk
    )
    DELETE FROM policy_chunk pc
    USING ranked r
    WHERE pc.id = r.id AND r.id <> r.keep_id;
END $$;

ALTER TABLE policy_chunk ADD CONSTRAINT policy_chunk_policy_document_id_section_ref_key
    UNIQUE (policy_document_id, section_ref);
