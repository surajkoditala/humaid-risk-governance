-- Synthetic users for local dev (100% synthetic per the hackathon's own constraint - never
-- connects to a real system or real identities).
INSERT INTO app_user (auth0_subject, email, display_name) VALUES
    ('seed|product-owner-1', 'po1@example.bank', 'Priya Owens'),
    ('seed|analyst-1', 'analyst1@example.bank', 'Amara Chen'),
    ('seed|analyst-2', 'analyst2@example.bank', 'Sam Okafor'),
    ('seed|committee-1', 'committee1@example.bank', 'Jordan Blake'),
    ('seed|committee-2', 'committee2@example.bank', 'Riley Voss'),
    ('seed|admin-1', 'admin1@example.bank', 'Taylor Finch'),
    -- Team lead's own dev identity - holds every role so local testing/demoing can exercise the
    -- full nav (union of all roles' screens) without switching "acting as" users. See Epic 11
    -- follow-up in docs/governance/user-roles-and-screens.md.
    ('seed|francis-1', 'mikodaray@gmail.com', 'Francis Daray')
ON CONFLICT (auth0_subject) DO NOTHING;

INSERT INTO app_user_role (user_id, role, reason)
SELECT u.id, r.role, 'Initial seed grant'
FROM app_user u
JOIN LATERAL (
    VALUES
        ('seed|product-owner-1', 'ProductOwner'),
        ('seed|analyst-1', 'Analyst'),
        ('seed|analyst-2', 'Analyst'),
        ('seed|committee-1', 'CommitteeMember'),
        ('seed|committee-2', 'CommitteeMember'),
        ('seed|admin-1', 'Admin'),
        ('seed|francis-1', 'ProductOwner'),
        ('seed|francis-1', 'Analyst'),
        ('seed|francis-1', 'CommitteeMember'),
        ('seed|francis-1', 'Admin')
) AS r(auth0_subject, role) ON r.auth0_subject = u.auth0_subject
ON CONFLICT (user_id, role) DO NOTHING;
