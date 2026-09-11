-- US-4.1: DocumentExtractionAiClient (real Claude call) writes one row per structured field.
CREATE OR REPLACE FUNCTION func_saveExtractedField(
    p_change_request_id UUID,
    p_attachment_id UUID,
    p_field_key TEXT,
    p_field_value TEXT,
    p_confidence NUMERIC,
    p_needs_review BOOLEAN,
    p_source_excerpt TEXT
) RETURNS UUID AS $$
DECLARE
    v_id UUID;
BEGIN
    INSERT INTO extracted_field (change_request_id, attachment_id, field_key, field_value, confidence, needs_review, source_excerpt, source)
    VALUES (p_change_request_id, p_attachment_id, p_field_key, p_field_value, p_confidence, p_needs_review, p_source_excerpt, 'AiExtracted')
    ON CONFLICT (change_request_id, field_key) DO UPDATE SET
        field_value = EXCLUDED.field_value, confidence = EXCLUDED.confidence,
        needs_review = EXCLUDED.needs_review, source_excerpt = EXCLUDED.source_excerpt,
        source = 'AiExtracted', updated_at = now()
    RETURNING id INTO v_id;

    INSERT INTO audit_event (change_request_id, entity_type, entity_id, action, actor_label, after_value)
    VALUES (p_change_request_id, 'ExtractedField', v_id, 'AiExtracted', 'system/AI',
            jsonb_build_object('fieldKey', p_field_key, 'value', p_field_value, 'confidence', p_confidence, 'needsReview', p_needs_review));

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;
