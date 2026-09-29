-- Maps an Auth0 identity to the three in-app roles from CLAUDE.md (Product Owner, FCRM Analyst,
-- Risk Committee Member) plus Admin for platform configuration (Epic 10).

CREATE TABLE app_user (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    auth0_subject TEXT NOT NULL UNIQUE, -- Auth0 'sub' claim (synthetic 'seed|...' values for seeded dev users)
    email TEXT NOT NULL,
    display_name TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Epic 11 follow-up: a user can hold more than one role, so role membership is a join table, not a
-- single app_user.role column - each grant gets its own actor and reason, audited the same way
-- workflow_rule/scoring_config already are (schema/010_scoring.sql, schema/012_configuration.sql),
-- rather than being an opaque diff of an array column. See docs/governance/user-roles-and-screens.md.
CREATE TABLE app_user_role (
    user_id UUID NOT NULL REFERENCES app_user(id),
    role TEXT NOT NULL CHECK (role IN ('ProductOwner','Analyst','CommitteeMember','Admin')),
    granted_by_user_id UUID REFERENCES app_user(id), -- null for a seed/system grant, same convention as audit_event.actor_user_id
    reason TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, role)
);
