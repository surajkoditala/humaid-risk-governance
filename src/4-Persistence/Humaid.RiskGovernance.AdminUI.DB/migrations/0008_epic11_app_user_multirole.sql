-- Epic 11 follow-up: a user can hold more than one role (docs/governance/user-roles-and-screens.md),
-- so app_user.role (a single column, real data) becomes app_user_role (a join table) - schema/003_users.sql
-- already covers a brand-new database, so this only needs to reach one that was deployed before
-- this change existed. Guarded per this folder's README: back-fill first, verify every row made
-- it across, only then drop the column that data came from.
CREATE TABLE IF NOT EXISTS app_user_role (
    user_id UUID NOT NULL REFERENCES app_user(id),
    role TEXT NOT NULL CHECK (role IN ('ProductOwner','Analyst','CommitteeMember','Admin')),
    granted_by_user_id UUID REFERENCES app_user(id),
    reason TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, role)
);

DO $$
DECLARE
    v_unbackfilled INT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'app_user' AND column_name = 'role') THEN
        RETURN; -- already migrated
    END IF;

    INSERT INTO app_user_role (user_id, role, reason)
    SELECT u.id, u.role, 'Migrated from single-role app_user.role column'
    FROM app_user u
    WHERE NOT EXISTS (SELECT 1 FROM app_user_role ur WHERE ur.user_id = u.id AND ur.role = u.role);

    SELECT count(*) INTO v_unbackfilled
    FROM app_user u
    WHERE NOT EXISTS (SELECT 1 FROM app_user_role ur WHERE ur.user_id = u.id AND ur.role = u.role);
    IF v_unbackfilled > 0 THEN
        RAISE EXCEPTION '% app_user row(s) did not receive an app_user_role grant during backfill - resolve manually before dropping app_user.role', v_unbackfilled;
    END IF;

    ALTER TABLE app_user DROP COLUMN role;
END $$;
