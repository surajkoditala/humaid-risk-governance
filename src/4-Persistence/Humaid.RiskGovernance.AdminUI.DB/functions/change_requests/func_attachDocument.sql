-- US-1.2: replacing a document creates a new versioned row, never overwrites the old one.
CREATE OR REPLACE FUNCTION func_attachDocument(
    p_change_request_id UUID,
    p_file_name TEXT,
    p_content_type TEXT,
    p_storage_path TEXT,
    p_extracted_text TEXT,
    p_uploaded_by_user_id UUID,
    p_supersedes_attachment_id UUID DEFAULT NULL
) RETURNS TABLE (id UUID, version_number INT) AS $$
DECLARE
    v_id UUID := gen_random_uuid();
    v_version INT := 1;
BEGIN
    IF p_supersedes_attachment_id IS NOT NULL THEN
        SELECT a.version_number + 1 INTO v_version FROM change_request_attachment a WHERE a.id = p_supersedes_attachment_id;
    END IF;

    INSERT INTO change_request_attachment (id, change_request_id, file_name, content_type, storage_path, extracted_text, version_number, uploaded_by_user_id)
    VALUES (v_id, p_change_request_id, p_file_name, p_content_type, p_storage_path, p_extracted_text, v_version, p_uploaded_by_user_id);

    IF p_supersedes_attachment_id IS NOT NULL THEN
        UPDATE change_request_attachment SET superseded_by_attachment_id = v_id WHERE id = p_supersedes_attachment_id;
    END IF;

    INSERT INTO audit_event (change_request_id, entity_type, entity_id, action, actor_user_id, actor_label, after_value)
    VALUES (p_change_request_id, 'Attachment', v_id, 'Uploaded', p_uploaded_by_user_id, 'human',
            jsonb_build_object('fileName', p_file_name, 'version', v_version));

    RETURN QUERY SELECT v_id, v_version;
END;
$$ LANGUAGE plpgsql;
