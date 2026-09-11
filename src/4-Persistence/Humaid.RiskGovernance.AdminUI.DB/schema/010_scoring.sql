-- Epic 7 — Risk Scoring Engine + Epic 10's scoring-config half.
--
-- Residual Risk = Inherent Risk - (Control Effectiveness x Mitigation Factor), per CLAUDE.md.
-- inherent_rating is a 1-5 scale (Low..Very High) and max_mitigation_factor is capped strictly
-- below 1.0, so with control_effectiveness in [0,1]: residual = inherent - (effectiveness x
-- mitigation) > inherent - 1 >= 1 - 1 = 0. Residual risk reaching zero is therefore mathematically
-- impossible given these two constraints, not merely discouraged - enforced again below by the
-- CHECK on assessment_risk_score.residual_rating as defense in depth.

CREATE TABLE control (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    risk_category_id UUID REFERENCES risk_category(id),
    name TEXT NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Versioned: a config change is a new row, never an in-place update to a live one (US-10.1) - so
-- an assessment created before the change keeps scoring against the config that was active when
-- it started (assessment.scoring_config_version_id, wired up below).
CREATE TABLE scoring_config (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    risk_category_id UUID NOT NULL REFERENCES risk_category(id),
    max_mitigation_factor NUMERIC(4,3) NOT NULL CHECK (max_mitigation_factor >= 0 AND max_mitigation_factor < 1.0),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_by_user_id UUID NOT NULL REFERENCES app_user(id),
    reason TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE assessment
    ADD CONSTRAINT fk_assessment_scoring_config_version
    FOREIGN KEY (scoring_config_version_id) REFERENCES scoring_config(id);

CREATE TABLE assessment_risk_score (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assessment_id UUID NOT NULL REFERENCES assessment(id),
    risk_category_id UUID NOT NULL REFERENCES risk_category(id),
    inherent_rating NUMERIC(5,2) NOT NULL CHECK (inherent_rating >= 1 AND inherent_rating <= 5),
    control_ids_credited JSONB NOT NULL DEFAULT '[]'::jsonb,
    control_effectiveness NUMERIC(4,3) NOT NULL CHECK (control_effectiveness >= 0 AND control_effectiveness <= 1),
    mitigation_factor_applied NUMERIC(4,3) NOT NULL CHECK (mitigation_factor_applied >= 0 AND mitigation_factor_applied < 1.0),
    residual_rating NUMERIC(5,2) NOT NULL CHECK (residual_rating > 0),
    is_override BOOLEAN NOT NULL DEFAULT false,
    override_reason TEXT,
    scored_by TEXT NOT NULL CHECK (scored_by IN ('System','Analyst')),
    created_by_user_id UUID REFERENCES app_user(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (assessment_id, risk_category_id),
    CHECK (NOT is_override OR override_reason IS NOT NULL)
);
