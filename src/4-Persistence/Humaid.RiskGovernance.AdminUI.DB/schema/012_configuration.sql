-- Epic 10's workflow-rule half — schema only in this pass (the scoring-config half is
-- scoring_config in 010_scoring.sql, which IS wired end to end).

CREATE TABLE workflow_rule (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rule_key TEXT NOT NULL, -- e.g. 'RequiresCommitteeVote.Vendor', 'CommitteeQuorum', 'EscalationThreshold.ResidualRating'
    rule_value JSONB NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_by_user_id UUID NOT NULL REFERENCES app_user(id),
    reason TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
