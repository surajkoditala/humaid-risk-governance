# Auth0 Setup — turning on real login

**Status:** not started. The code is ready for this (`AppUserClaimsTransformation`,
`DevBypassAuthHandler`'s fail-closed fallback — see `docs/governance/access-control-matrix.md`);
what's missing is an actual Auth0 tenant and application. This is a walkthrough of the Auth0
dashboard steps, written so they can be done in one sitting without re-deriving anything.

Auth0 only ever establishes **who is logging in** (an identity — the token's `sub` claim). It does
**not** decide what that person can do here — the app never reads an Auth0 role or permission.
`AppUserClaimsTransformation` looks the `sub` up in `app_user` and takes the role from that row
instead. So the Auth0 side of this is deliberately small: get a login working, nothing more.

## 1. Create the tenant (if the team doesn't have one yet)

1. Sign up at <https://auth0.com> (or log in if the team already has a tenant for something else).
2. Pick a region close to the team/reviewers — doesn't need to match Azure's `eastus2`.
3. Note the tenant's domain, e.g. `humaid-risk-governance.us.auth0.com` — this is `AUTH0_DOMAIN`
   (without the `https://`).

## 2. Create the API (this is what `AUTH0_AUDIENCE` identifies)

**Applications → APIs → Create API**
- Name: `HumAId Risk Governance API`
- Identifier: any URI-shaped string, doesn't need to resolve — e.g.
  `https://api.humaid-risk-governance` (a convention, not a real endpoint). This value is both
  `AUTH0_AUDIENCE` (backend) and `VITE_AUTH0_AUDIENCE` (frontend) — they must match exactly.
- Signing Algorithm: RS256 (the default; `Program.cs`'s `AddJwtBearer` expects this).

## 3. Create the application (this is what the webapp logs in through)

**Applications → Applications → Create Application**
- Name: `HumAId Risk Governance Workbench`
- Type: **Single Page Application**
- Under the new application's **Settings** tab, set:
  - **Allowed Callback URLs:** `http://localhost:3000, https://<deployed webapp origin>`
  - **Allowed Logout URLs:** same two
  - **Allowed Web Origins:** same two
  - (the deployed origin is the Workbench Container App's URL — `az containerapp show --name
    ca-gh-hrg-workbench-dev --resource-group rg-gh-dev --query
    properties.configuration.ingress.fqdn`)
- Note the **Domain** (same as step 1) and **Client ID**.

No roles, no rules, no Actions — skip anything in the dashboard about permissions or roles. That
model lives in `app_user`, not here.

## 4. Provision each real login to an `app_user` row

This is the step it's easy to skip and then have login "work" but every screen show 403. The
seeded `app_user` rows use synthetic subjects (`seed|product-owner-1`, etc.) that no real Auth0
login will ever present — `AppUserClaimsTransformation` will resolve a real login to *no* role
until its actual `sub` is written into the matching row.

1. Have each of the four team members log in once through the webapp (once Auth0 is wired — see
   step 5) and open the browser's dev tools → Application → Local Storage, or decode the Auth0
   access token at <https://jwt.io>, to read their own `sub` claim (looks like
   `auth0|64f...` or `google-oauth2|...`, depending on how they signed in).
2. Update the matching seeded row (by email/role) to that real subject:
   ```sql
   UPDATE app_user SET auth0_subject = '<real sub from step 1>' WHERE email = 'analyst1@example.bank';
   ```
   Repeat once per demo identity needed (at least one Product Owner, one Analyst, one Committee
   Member; one Admin if the config screen is part of the demo).
3. Anyone who logs in without a matching row stays authenticated but gets no role — every
   role-protected screen 403s for them (working as designed, not a bug — see
   `docs/governance/access-control-matrix.md`).

## 5. Wire the values in

**Locally (optional — only if testing real login, not just the demo identities):**
- `webapp/.env.local`: `VITE_AUTH0_DOMAIN`, `VITE_AUTH0_CLIENT_ID`, `VITE_AUTH0_AUDIENCE` from
  steps 1–3.
- Backend: set `AUTH0_DOMAIN` / `AUTH0_AUDIENCE` as environment variables before `dotnet run`.
- **Setting these locally turns OFF the "acting as" dev switcher everywhere** (frontend and
  backend both fall back to real login only when their own Auth0 config is blank) — most of the
  team should probably leave local dev alone and only configure Auth0 in the deployed environment.

**In the deployed dev environment:**
- **Backend (runtime config):** `AUTH0_DOMAIN` and `AUTH0_AUDIENCE` as Container App env vars (or
  Key Vault secret references, matching how `ANTHROPIC-API-KEY`/`FOUNDRY-API-KEY` are already set
  up) on `ca-gh-hrg-workbench-dev`.
- **Frontend (build-time config — this is the step that's easy to miss):** the webapp is baked
  into the same image at `docker build` time (PR #49), and Vite inlines `VITE_*` values into the
  bundle at that point, not at container start. Fill in `frontendAuth0Domain` /
  `frontendAuth0ClientId` / `frontendAuth0Audience` in
  `.azure-pipelines/workbench/templates/variables.yml` — see the "Frontend Auth0 config is a
  build-time value" section of `ops/README.md` for why a Container App env var alone won't do it.
  The next Workbench pipeline run after that edit ships a build with real login. (Filled in for
  dev on 2026-10-08 — the first deployed images were built with these empty and showed "Auth0 is
  not configured". If it ever reappears, check the deployed bundle for the tenant domain first.)

## 6. Verify

- `GET /api/User/Me` (through the deployed app, signed in) returns the caller's own resolved
  identity and role — confirms the whole chain (Auth0 → `AppUserClaimsTransformation` → `app_user`)
  end to end.
- Each of the four demo identities can reach exactly the screens `access-control-matrix.md` says
  their role can, and gets a 403 (not a silent 200) on the rest.
