-- US-4.2: reason is only mandatory when the edit materially changes the field's meaning - that
-- judgment call is made by the service layer (Services/DocumentExtraction), not here, so p_reason
-- is nullable at the DB level.
CREATE OR REPLACE FUNCTION func_correctExtractedField(
    p_change_request_id UUID,
    p_field_key TEXT,
    p_new_value TEXT,
    p_reason TEXT,
    p_actor_user_id UUID
) RETURNS UUID AS $$
DECLARE
    v_id UUID;
    v_before JSONB;
BEGIN
    SELECT to_jsonb(f) INTO v_before FROM extracted_field f WHERE change_request_id = p_change_request_id AND field_key = p_field_key;

    UPDATE extracted_field
    SET field_value = p_new_value, source = 'AnalystCorrected', needs_review = false,
        confidence = NULL, updated_by_user_id = p_actor_user_id, updated_at = now()
    WHERE change_request_id = p_change_request_id AND field_key = p_field_key
    RETURNING id INTO v_id;

    INSERT INTO audit_event (change_request_id, entity_type, entity_id, action, actor_user_id, actor_label, before_value, after_value, reason)
    VALUES (p_change_request_id, 'ExtractedField', v_id, 'Corrected', p_actor_user_id, 'human',
            v_before, jsonb_build_object('fieldKey', p_field_key, 'value', p_new_value), p_reason);

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;
