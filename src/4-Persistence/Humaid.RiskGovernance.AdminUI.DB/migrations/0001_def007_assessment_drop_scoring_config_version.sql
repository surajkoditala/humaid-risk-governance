-- DEF-016 redesign (schema/010_scoring.sql, schema/005_assessments.sql): scoring_config is
-- versioned per risk_category (up to 4 rows at once), which a single assessment-level FK can't
-- pin across every category - func_calculateAndSaveRiskScore now selects the config in force by
-- assessment.created_at instead. This column and its FK were never populated by any code path.
ALTER TABLE assessment DROP COLUMN IF EXISTS scoring_config_version_id;
