-- US-3.1: deterministic Postgres full-text search - deliberately NOT an LLM/embedding call.
-- Ranking policy text by keyword relevance is a solved search problem; spending an LLM call on it
-- would add latency/cost/nondeterminism for no accuracy gain. See
-- docs/governance/human-in-the-loop-gates.md.
--
-- Forgiving on purpose, because an analyst may not know the exact wording of an excerpt:
--   * Empty (or too-short) text browses: every excerpt, narrowed by category if one is given.
--   * Each typed word matches as a prefix ("benef" finds "beneficial"), and a chunk needs to match
--     only ANY of the words, not all of them; more matching words rank higher.
--   * A word that starts a word in the excerpt's topic (the part of section_ref after " - ") ranks
--     higher still, so typing a topic puts that excerpt first.
-- Words are reduced to letters and digits before they reach the tsquery, so user text can never
-- inject tsquery syntax. Typos are not corrected (that would need pg_trgm).
CREATE OR REPLACE FUNCTION func_searchPolicyChunks(
    p_query_text TEXT,
    p_risk_category_id UUID DEFAULT NULL,
    p_top_k INT DEFAULT 5
) RETURNS TABLE (
    id UUID, policy_document_id UUID, document_title TEXT, source_url TEXT, effective_date DATE,
    section_ref TEXT, chunk_text TEXT, rank REAL
) AS $$
DECLARE
    v_tokens TEXT[];
    v_query TSQUERY;
    v_limit INT := LEAST(GREATEST(COALESCE(p_top_k, 5), 1), 50);
BEGIN
    SELECT array_agg(DISTINCT t) INTO v_tokens
    FROM unnest(regexp_split_to_array(lower(COALESCE(p_query_text, '')), '[^[:alnum:]]+')) AS t
    WHERE length(t) >= 2;

    IF v_tokens IS NULL THEN
        RETURN QUERY
        SELECT pc.id, pc.policy_document_id, pd.title, pd.source_url, pd.effective_date, pc.section_ref, pc.chunk_text,
               0::REAL AS rank
        FROM policy_chunk pc
        JOIN policy_document pd ON pd.id = pc.policy_document_id
        WHERE p_risk_category_id IS NULL OR pc.risk_category_id = p_risk_category_id
        ORDER BY pc.section_ref
        LIMIT v_limit;
        RETURN;
    END IF;

    SELECT to_tsquery('english', string_agg(t || ':*', ' | ')) INTO v_query FROM unnest(v_tokens) AS t;

    RETURN QUERY
    SELECT m.id, m.policy_document_id, m.title, m.source_url, m.effective_date, m.section_ref, m.chunk_text,
           (m.text_rank + 0.2 * m.topic_hits)::REAL AS rank
    FROM (
        SELECT pc.id, pc.policy_document_id, pd.title, pd.source_url, pd.effective_date, pc.section_ref, pc.chunk_text,
               ts_rank(pc.search_vector, v_query) AS text_rank,
               (pc.search_vector @@ v_query) AS text_match,
               (SELECT count(*) FROM unnest(v_tokens) AS t
                WHERE lower(COALESCE(NULLIF(split_part(pc.section_ref, ' - ', 2), ''), pc.section_ref)) ~ ('\m' || t)) AS topic_hits
        FROM policy_chunk pc
        JOIN policy_document pd ON pd.id = pc.policy_document_id
        WHERE (p_risk_category_id IS NULL OR pc.risk_category_id = p_risk_category_id)
    ) m
    WHERE m.text_match OR m.topic_hits > 0
    ORDER BY (m.text_rank + 0.2 * m.topic_hits) DESC, m.section_ref
    LIMIT v_limit;
END;
$$ LANGUAGE plpgsql STABLE;
