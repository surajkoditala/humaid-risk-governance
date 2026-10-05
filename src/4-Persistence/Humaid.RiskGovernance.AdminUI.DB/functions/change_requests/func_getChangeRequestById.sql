-- Output column is named type_specific_fields_json (not type_specific_fields) so Dapper's
-- MatchNamesWithUnderscores maps it onto ChangeRequest.TypeSpecificFieldsJson - RETURNS TABLE
-- column names become the actual result-set column names regardless of the SELECT body's own
-- aliases, so this rename alone is enough; the SELECT below is unchanged.
CREATE OR REPLACE FUNCTION func_getChangeRequestById(p_change_request_id UUID)
RETURNS TABLE (
    id UUID, request_number TEXT, change_type TEXT, title TEXT, description TEXT,
    type_specific_fields_json JSONB, status TEXT, submitted_by_user_id UUID, submitted_at TIMESTAMPTZ
) AS $$
    SELECT c.id, c.request_number, c.change_type, c.title, c.description, c.type_specific_fields,
           c.status, c.submitted_by_user_id, c.submitted_at
    FROM change_request c WHERE c.id = p_change_request_id;
$$ LANGUAGE sql STABLE;
