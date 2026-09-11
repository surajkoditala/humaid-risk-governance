-- Synthetic users for local dev (100% synthetic per the hackathon's own constraint - never
-- connects to a real system or real identities).
INSERT INTO app_user (auth0_subject, email, display_name, role) VALUES
    ('seed|product-owner-1', 'po1@example.bank', 'Priya Owens', 'ProductOwner'),
    ('seed|analyst-1', 'analyst1@example.bank', 'Amara Chen', 'Analyst'),
    ('seed|analyst-2', 'analyst2@example.bank', 'Sam Okafor', 'Analyst'),
    ('seed|committee-1', 'committee1@example.bank', 'Jordan Blake', 'CommitteeMember'),
    ('seed|committee-2', 'committee2@example.bank', 'Riley Voss', 'CommitteeMember'),
    ('seed|admin-1', 'admin1@example.bank', 'Taylor Finch', 'Admin')
ON CONFLICT (auth0_subject) DO NOTHING;
