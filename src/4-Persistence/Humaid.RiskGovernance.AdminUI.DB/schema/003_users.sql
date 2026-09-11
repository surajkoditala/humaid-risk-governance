-- Maps an Auth0 identity to the three in-app roles from CLAUDE.md (Product Owner, FCRM Analyst,
-- Risk Committee Member) plus Admin for platform configuration (Epic 10).

CREATE TABLE app_user (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    auth0_subject TEXT NOT NULL UNIQUE, -- Auth0 'sub' claim (synthetic 'seed|...' values for seeded dev users)
    email TEXT NOT NULL,
    display_name TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('ProductOwner','Analyst','CommitteeMember','Admin')),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
