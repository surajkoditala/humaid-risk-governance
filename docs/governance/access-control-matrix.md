# Access Control Matrix — Epic 11

**US-11.1 AC4:** "a documented matrix maps each of the three roles ... to every action, and each
endpoint behaviour matches it." This is that matrix. It is pinned against the code by
`tests/Humaid.RiskGovernance.AdminUI.UnitTests/Auth/AccessControlMatrixTests.cs`, which reflects
over every controller action and fails if one is missing a role/policy restriction, so this table
cannot silently drift from what's enforced.

## Four roles, not three

`app_user.role` (`schema/003_users.sql`) and the webapp's own nav (`App.jsx`) already had a fourth
role, **Admin**, before this epic started — it owns platform configuration (Epic 10) in the
existing UI, separate from Product Owner, FCRM Analyst, and Risk Committee Member. Epic 11 kept
that split rather than folding Admin into Analyst: the person who tunes scoring thresholds and
workflow rules should not be the same person who scores an assessment or votes on it. `AppRoles`
(`Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Users`) is the source of truth for role names.

## How a role is established

- **Real login (Auth0):** `AppUserClaimsTransformation` resolves the validated token's `sub` claim
  to an `app_user` row via `func_getUserByAuth0Subject` and adds that row's `id`/`role` as claims —
  discarding any role claim already on the incoming identity first. A caller with no matching,
  active `app_user` row stays authenticated but gets no role, so every role-protected action
  refuses them with 403.
- **Local dev (no Auth0 tenant):** `DevBypassAuthHandler` reads the `X-Dev-User-Id` header the
  webapp's "acting as" switcher sets (`webapp/src/auth/devUserId.js` / `DevUserContext.jsx`); the
  same claims transformation resolves that id via `func_getUserById`, so the exact same role checks
  apply to a switched-in local user as to a real one. This path activates only when `AUTH0_DOMAIN`
  is unset **and** the environment is Development **and** the process is not running in Azure
  Container Apps (`CONTAINER_APP_NAME` unset) — the last check closes DEF-010 (the deployed dev app
  ran with the bypass active because `ASPNETCORE_ENVIRONMENT=Development` alone used to be enough).
  Outside that combination, a missing `AUTH0_DOMAIN`/`AUTH0_AUDIENCE` now fails the app at startup
  instead of starting with no way to validate a token.
- **The acting-user id in a request body/form** (`ActorUserId`, `SubmittedByUserId`, and so on) is
  still there — removing it from every model, SQL function, and webapp call is a larger refactor the
  existing `NOTE` in `ChangeRequestController.cs` already flagged as a later pass, not this one.
  What Epic 11 adds is `BaseApiController.RequireSelf<T>`: every action that takes one of these
  fields calls it first, and it rejects the call unless that id is the caller's own resolved
  `app_user.id`. A caller can therefore still name themselves in the payload, but can no longer name
  anyone else — closing DEF-002 (a Product Owner's id in `CommitteeMemberUserId` used to count
  toward committee quorum).

## The matrix

Legend: **PO** Product Owner · **AN** Analyst · **CM** Committee Member · **AD** Admin · **Self**
`RequireSelf` checked on the named field · **Own CR** the action also checks the fetched change
request's `SubmittedByUserId` against the caller (Product Owner only; Analyst is unrestricted).

### Epic 1 — Change Request Intake (`ChangeRequestController`)
| Action | PO | AN | CM | AD | Notes |
|---|---|---|---|---|---|
| `POST Submit` | ✅ Self | | | | US-1.1 |
| `GET {id}` | ✅ Own CR | ✅ | | | |
| `GET ForUser/{userId}` | ✅ Self | | | | "My Requests" |
| `GET` (all) | | ✅ | | | The analyst inbox |
| `POST AttachDocument` | ✅ Self, Own CR | | | | US-1.2 |
| `POST AttachDocumentFile` | ✅ Self, Own CR | | | | |
| `GET {id}/Attachments` | ✅ Own CR | ✅ | | | |
| `POST {id}/RequestClarification` | | ✅ Self | | | Analyst asks the owner — US-1.3 AC3 |

### Epic 2 — Risk Categorization `[AI]` (`CategoryMappingController`)
| Action | PO | AN | CM | AD | Notes |
|---|---|---|---|---|---|
| `POST Propose` | | ✅ | | | US-2.1 |
| `POST Override` | | ✅ Self | | | US-2.2 |
| `GET Categories` | | ✅ | | ✅ | Also backs the Admin config screen's category dropdown |
| `GET {assessmentId}` | | ✅ | | | |

### Epic 3 — Policy Research (`PolicyResearchController`)
| Action | PO | AN | CM | AD | Notes |
|---|---|---|---|---|---|
| `GET Search` | | ✅ | | | Deterministic search, not AI |
| `POST RecordReliance` | | ✅ Self | | | US-3.2 |
| `GET {assessmentId}/Reliance` | | ✅ | | | |

### Epic 4 — Document Extraction `[AI]` (`DocumentExtractionController`)
| Action | PO | AN | CM | AD | Notes |
|---|---|---|---|---|---|
| `POST Extract` | | ✅ | | | US-4.1 |
| `POST Correct` | | ✅ Self | | | US-4.2 |
| `GET {changeRequestId}` | | ✅ | | | |

### Epic 5 — AI-Drafted Narrative (`NarrativeController`)
| Action | PO | AN | CM | AD | Notes |
|---|---|---|---|---|---|
| `POST Draft` | | ✅ | | | US-5.1 / US-5.2 |
| `POST Review` | | ✅ Self | | | US-6.3 (accept as-is) |
| `POST Edit` | | ✅ Self | | | US-6.1 |
| `GET {assessmentId}` | | ✅ | | | |

### Epic 6/7 — Assessment & Scoring (`AssessmentController`, `ScoringController`)
| Action | PO | AN | CM | AD | Notes |
|---|---|---|---|---|---|
| `POST Assessment/OpenWorkspace/{id}` | | ✅ | | | |
| `GET Assessment/ByChangeRequest/{id}` | | ✅ | | | |
| `GET Assessment/{id}/Readiness` | | ✅ | | | |
| `POST Assessment/{id}/Finalize` | | ✅ Self | | | US-6.3 — closes part of DEF-002 (Critical; "as the finalizing analyst" is one of its three named examples). **Does not touch DEF-001** (the readiness gate passing vacuously for an empty assessment) — that is a separate, still-open defect in `AssessmentService.CheckReadinessAsync`, unrelated to who is allowed to call Finalize |
| `POST Scoring/Config` | | | | ✅ Self | US-10.1 — Admin, not Analyst, mirrors `WorkflowRuleController` |
| `POST Scoring/Calculate` | | ✅ | | | US-7.1 |
| `POST Scoring/Override` | | ✅ Self | | | US-7.2 |
| `GET Scoring/{assessmentId}` | | ✅ | | | |
| `GET Scoring/Controls/{riskCategoryId}` | | ✅ | | ✅ | Not yet wired to a webapp screen |

### Epic 8 — Committee (`CommitteeController`)
| Action | PO | AN | CM | AD | Notes |
|---|---|---|---|---|---|
| `POST Route` | | ✅ Self | | | US-8.1 |
| `GET Queue` | | | ✅ | | |
| `POST Vote` | | | ✅ Self | | **US-8.2 — closes DEF-002 (Critical): only a Committee Member may vote, and only as themselves, so a Product Owner's id can no longer be accepted as `CommitteeMemberUserId` and counted toward quorum** |
| `GET {assessmentId}/Votes` | | ✅ | ✅ | | |
| `GET {assessmentId}/Decision` | | ✅ | ✅ | | US-8.3 |

### Epic 9 — Audit Trail (`AuditController`)
| Action | PO | AN | CM | AD | Notes |
|---|---|---|---|---|---|
| `GET {changeRequestId}` | | ✅ | | ✅ | US-9.1. "Auditor/Examiner" isn't an `AppRoles` value — mapped to Analyst + Admin, see below |
| `GET {changeRequestId}/Export` | | ✅ | | ✅ | US-9.3 |

### Epic 10 — Platform Configuration (`WorkflowRuleController`)
| Action | PO | AN | CM | AD | Notes |
|---|---|---|---|---|---|
| `GET` (rules) | | | | ✅ | US-10.2 |
| `POST` (upsert) | | | | ✅ Self | |

### Epic 14 — Mock Systems / Data Ingestion (`DataIngestionController`)
| Action | PO | AN | CM | AD | Notes |
|---|---|---|---|---|---|
| `GET MockCustomers` / `MockProducts` / `MockVendors` | ✅ | | | | US-14.3 — the intake lookup, not a directory search |
| `GET Snapshot/{changeRequestId}` | | ✅ | | | US-14.4. Not yet wired to a webapp screen |

### Users (`UserController`)
| Action | PO | AN | CM | AD | Notes |
|---|---|---|---|---|---|
| `GET` (all users) | Open in local dev only | | | ✅ (real auth) | `AccessPolicies.UserDirectory` — powers the dev "acting as" switcher; an Admin-only directory once Auth0 is on |
| `GET Me` | ✅ | ✅ | ✅ | ✅ | Any authenticated role — returns only the caller's own resolved identity |

### Unrestricted by design
- **`PingController.Get`** — documented reference vertical slice, callable before Auth0 is even
  configured.

## Open items this matrix surfaces, not resolves

- **"Auditor/Examiner" (US-9.1/US-9.3) isn't one of the four `AppRoles`.** Mapped to Analyst + Admin
  for now; add a dedicated role if the team wants examiner access that doesn't imply either.
- **Whether a Product Owner may see their own linked-record snapshot** (`DataIngestion/Snapshot`)
  is open question #1 in `CLAUDE.md` (analyst scoring rationale visibility) — scoped to Analyst only
  until that's decided.
- **`Scoring/Controls`** isn't called by the webapp yet; its role list (Analyst + Admin) is a
  placeholder pending whichever screen ends up using it.
