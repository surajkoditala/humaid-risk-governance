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

    -- AI review on PR #60: an earlier version of this repoint used a NOT EXISTS guard evaluated
    -- once per row - if one assessment had reliance decisions on two different duplicate chunks in
    -- the same group (and none yet on the surviving chunk), the guard passed for both rows and a
    -- single UPDATE tried to point both at keep_id, violating the (assessment_id, policy_chunk_id)
    -- constraint that's still active until migration 0003 runs, and halting startup.
    --
    -- Ranking instead: every reliance row on any chunk in a duplicate group - the surviving chunk
    -- included, in case it already has its own decision - competes for one survivor per
    -- (assessment_id, keep_id), newest decision wins (matches func_recordPolicyReliance's own ON
    -- CONFLICT DO UPDATE semantics). Losers are deleted before the winner is ever repointed, so at
    -- most one row can hold (assessment_id, keep_id) at a time - no window where two can collide.
    WITH ranked_chunks AS (
        SELECT id, policy_document_id, section_ref,
               first_value(id) OVER (PARTITION BY policy_document_id, section_ref ORDER BY id) AS keep_id,
               count(*) OVER (PARTITION BY policy_document_id, section_ref) AS group_size
        FROM policy_chunk
    ),
    affected_reliance AS (
        SELECT apr.id, rc.keep_id,
               row_number() OVER (PARTITION BY apr.assessment_id, rc.keep_id ORDER BY apr.decided_at DESC, apr.id DESC) AS rn
        FROM assessment_policy_reliance apr
        JOIN ranked_chunks rc ON rc.id = apr.policy_chunk_id
        WHERE rc.group_size > 1
    )
    DELETE FROM assessment_policy_reliance apr
    USING affected_reliance ar
    WHERE apr.id = ar.id AND ar.rn > 1;

    -- Exactly one reliance row per (assessment_id, keep_id) survives the delete above - safe to
    -- repoint unconditionally now, no collision possible.
    WITH ranked_chunks AS (
        SELECT id, policy_document_id, section_ref,
               first_value(id) OVER (PARTITION BY policy_document_id, section_ref ORDER BY id) AS keep_id
        FROM policy_chunk
    )
    UPDATE assessment_policy_reliance apr
    SET policy_chunk_id = rc.keep_id
    FROM ranked_chunks rc
    WHERE apr.policy_chunk_id = rc.id AND rc.id <> rc.keep_id;

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
