CREATE OR REPLACE FUNCTION func_getExtractedFields(p_change_request_id UUID)
RETURNS TABLE (
    id UUID, field_key TEXT, field_value TEXT, confidence NUMERIC,
    needs_review BOOLEAN, source_excerpt TEXT, source TEXT, updated_at TIMESTAMPTZ
) AS $$
    SELECT f.id, f.field_key, f.field_value, f.confidence, f.needs_review, f.source_excerpt, f.source, f.updated_at
    FROM extracted_field f WHERE f.change_request_id = p_change_request_id;
$$ LANGUAGE sql STABLE;
