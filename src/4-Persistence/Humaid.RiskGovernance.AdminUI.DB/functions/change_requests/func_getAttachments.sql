CREATE OR REPLACE FUNCTION func_getAttachments(p_change_request_id UUID)
RETURNS TABLE (id UUID, file_name TEXT, content_type TEXT, storage_path TEXT, version_number INT, uploaded_at TIMESTAMPTZ) AS $$
    SELECT a.id, a.file_name, a.content_type, a.storage_path, a.version_number, a.uploaded_at
    FROM change_request_attachment a
    WHERE a.change_request_id = p_change_request_id AND a.superseded_by_attachment_id IS NULL
    ORDER BY a.uploaded_at;
$$ LANGUAGE sql STABLE;
