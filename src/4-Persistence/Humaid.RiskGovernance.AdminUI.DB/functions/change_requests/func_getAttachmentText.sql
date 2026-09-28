-- DEF-020: extraction must run on the attachment's own server-extracted text, not whatever the
-- client happened to pass as documentText (the webapp was sending the file NAME). This lets the
-- extraction service load the text itself by attachmentId.
CREATE OR REPLACE FUNCTION func_getAttachmentText(p_attachment_id UUID)
RETURNS TEXT AS $$
    SELECT extracted_text FROM change_request_attachment WHERE id = p_attachment_id;
$$ LANGUAGE sql STABLE;
