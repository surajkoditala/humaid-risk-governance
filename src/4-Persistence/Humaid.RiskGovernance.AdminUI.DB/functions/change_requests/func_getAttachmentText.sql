-- DEF-020: extraction must run on the attachment's own server-extracted text, not whatever the
-- client happened to pass as documentText (the webapp was sending the file NAME). This lets the
-- extraction service load the text itself by attachmentId.
--
-- AI review on PR #60: attachmentId alone let a caller pair one change request's id with another
-- request's attachmentId and extract (and save) that other request's document text under its own
-- record. p_change_request_id must match too - a mismatch returns NULL, same as "no text yet",
-- rather than revealing whether the attachment exists under a different request.
CREATE OR REPLACE FUNCTION func_getAttachmentText(p_change_request_id UUID, p_attachment_id UUID)
RETURNS TEXT AS $$
    SELECT extracted_text FROM change_request_attachment
    WHERE id = p_attachment_id AND change_request_id = p_change_request_id;
$$ LANGUAGE sql STABLE;
