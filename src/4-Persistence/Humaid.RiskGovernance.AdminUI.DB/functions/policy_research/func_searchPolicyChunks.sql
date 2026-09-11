-- US-3.1: deterministic Postgres full-text search - deliberately NOT an LLM/embedding call.
-- Ranking policy text by keyword relevance is a solved search problem; spending an LLM call on it
-- would add latency/cost/nondeterminism for no accuracy gain. See
-- docs/governance/human-in-the-loop-gates.md.
CREATE OR REPLACE FUNCTION func_searchPolicyChunks(
    p_query_text TEXT,
    p_risk_category_id UUID DEFAULT NULL,
    p_top_k INT DEFAULT 5
) RETURNS TABLE (
    id UUID, policy_document_id UUID, document_title TEXT, source_url TEXT, effective_date DATE,
    section_ref TEXT, chunk_text TEXT, rank REAL
) AS $$
    SELECT pc.id, pc.policy_document_id, pd.title, pd.source_url, pd.effective_date, pc.section_ref, pc.chunk_text,
           ts_rank(pc.search_vector, plainto_tsquery('english', p_query_text)) AS rank
    FROM policy_chunk pc
    JOIN policy_document pd ON pd.id = pc.policy_document_id
    WHERE (p_risk_category_id IS NULL OR pc.risk_category_id = p_risk_category_id)
      AND pc.search_vector @@ plainto_tsquery('english', p_query_text)
    ORDER BY rank DESC
    LIMIT p_top_k;
$$ LANGUAGE sql STABLE;
