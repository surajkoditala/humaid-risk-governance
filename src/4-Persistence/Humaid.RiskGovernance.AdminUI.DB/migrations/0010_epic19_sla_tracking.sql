-- Epic 19 (SLA tracking): brings databases deployed BEFORE this epic up to date. A brand-new database
-- gets the same objects from schema/015_sla.sql via deploy_all.sql, so this file is recorded as
-- already-applied there. Identical DDL to schema/015_sla.sql by design (every statement is IF NOT
-- EXISTS / DROP IF EXISTS, so it is safe either way). The default configuration and the backfill of
-- existing requests are in seed/seed_sla_config.sql, which runs after this and after functions/.


CREATE TABLE IF NOT EXISTS sla_config (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    version_number INT NOT NULL UNIQUE,
    at_risk_threshold_pct INT NOT NULL CHECK (at_risk_threshold_pct BETWEEN 1 AND 99), -- % of the target after which a request is "At risk"
    pause_on_clarification BOOLEAN NOT NULL DEFAULT true, -- time waiting on the Product Owner is not charged to the analyst stage
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_by_user_id UUID NOT NULL REFERENCES app_user(id),
    reason TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- At most one active version at a time.
CREATE UNIQUE INDEX IF NOT EXISTS ux_sla_config_single_active ON sla_config ((is_active)) WHERE is_active;

CREATE TABLE IF NOT EXISTS sla_target (
    sla_config_id UUID NOT NULL REFERENCES sla_config(id),
    change_type TEXT NOT NULL CHECK (change_type IN ('Product','Feature','Process','Vendor','Geography','CustomerSegment')),
    stage TEXT NOT NULL CHECK (stage IN ('Submitted','InAssessment','PendingCommittee','EndToEnd')),
    target_business_days INT NOT NULL CHECK (target_business_days > 0),
    PRIMARY KEY (sla_config_id, change_type, stage)
);

CREATE TABLE IF NOT EXISTS sla_holiday (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    holiday_date DATE NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true, -- removing a holiday deactivates it (audited), never deletes the row
    created_by_user_id UUID NOT NULL REFERENCES app_user(id),
    reason TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_sla_holiday_active_date ON sla_holiday (holiday_date) WHERE is_active;

-- One row per change request: which SLA version it is pinned to, and its end-to-end result once decided.
CREATE TABLE IF NOT EXISTS change_request_sla (
    change_request_id UUID PRIMARY KEY REFERENCES change_request(id),
    sla_config_id UUID REFERENCES sla_config(id), -- null only if no SLA version existed at submission
    decided_at TIMESTAMPTZ,
    e2e_actual_business_days INT, -- frozen once decided; never recomputed if configuration changes later
    e2e_met BOOLEAN
);

-- One row per stage a request has been in. Closed rows (left_at set) are frozen: actual duration and
-- whether the SLA was met are kept permanently (US-19.2 AC3).
CREATE TABLE IF NOT EXISTS change_request_stage_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    change_request_id UUID NOT NULL REFERENCES change_request(id),
    stage TEXT NOT NULL CHECK (stage IN ('Submitted','InAssessment','PendingCommittee')),
    entered_at TIMESTAMPTZ NOT NULL,
    left_at TIMESTAMPTZ,
    target_business_days INT, -- snapshot of the pinned version's target when the stage was entered; null if untracked
    actual_business_days INT, -- charged business days (waiting on the Product Owner excluded when configured)
    met_sla BOOLEAN
);
CREATE INDEX IF NOT EXISTS idx_stage_history_request ON change_request_stage_history (change_request_id, entered_at);
-- A request is in exactly one stage at a time.
CREATE UNIQUE INDEX IF NOT EXISTS ux_stage_history_one_open ON change_request_stage_history (change_request_id) WHERE left_at IS NULL;

-- The ONE capture point: change_request.status is changed by several different functions, so a
-- trigger records every transition instead of each of them needing to remember to. The triggers stay
-- deliberately thin - the logic lives in functions/sla/func_slaRecordTransition.sql, which (unlike a
-- trigger function defined here) can be changed later without a new migration.
CREATE OR REPLACE FUNCTION fn_trg_sla_request_submitted() RETURNS TRIGGER AS $$
BEGIN
    PERFORM fn_sla_record_transition(NEW.id, NULL, NEW.status);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_trg_sla_status_changed() RETURNS TRIGGER AS $$
BEGIN
    PERFORM fn_sla_record_transition(NEW.id, OLD.status, NEW.status);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sla_request_submitted ON change_request;
CREATE TRIGGER trg_sla_request_submitted
    AFTER INSERT ON change_request
    FOR EACH ROW EXECUTE FUNCTION fn_trg_sla_request_submitted();

DROP TRIGGER IF EXISTS trg_sla_status_changed ON change_request;
CREATE TRIGGER trg_sla_status_changed
    AFTER UPDATE OF status ON change_request
    FOR EACH ROW WHEN (OLD.status IS DISTINCT FROM NEW.status)
    EXECUTE FUNCTION fn_trg_sla_status_changed();
