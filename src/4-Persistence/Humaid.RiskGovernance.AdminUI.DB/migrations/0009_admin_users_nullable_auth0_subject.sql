-- Admin user-management screen: an Admin creates a user by email/display name/role(s) before that
-- person has ever logged in, so there is no Auth0 'sub' to store yet. Postgres UNIQUE already
-- allows any number of NULLs (unlike PRIMARY KEY), so dropping NOT NULL is the whole change - a
-- real login is still guaranteed unique once one is linked (func_setUserAuth0Subject).
ALTER TABLE app_user ALTER COLUMN auth0_subject DROP NOT NULL;
