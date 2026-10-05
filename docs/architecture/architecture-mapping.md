# Architecture mapping: CLAUDE.md's suggestion vs. what we actually built

`CLAUDE.md` (the hackathon brief) proposes a modular, multi-tier application laid out as
`RAW.Api / RAW.Application / RAW.Domain / RAW.Infrastructure / RAW.AI`, with EF Core against
PostgreSQL. This repo already existed as a 5-layer Clean Architecture scaffold
(`1-API / 2-Infrastructure / 3-Service / 4-Persistence / 5-Presentation`, Dapper + stored
procedures, no ORM) before the brief arrived. Rather than restructure to match the brief
literally, we kept the existing architecture and mapped the brief's *ideas* onto it.

| CLAUDE.md suggests | We use instead | Why |
|---|---|---|
| `RAW.Domain` (entities/VOs, zero deps) | Models live in `2-Infrastructure/Models/<Module>/` | Our `2-Infrastructure` is already a zero-implementation, interfaces-and-models layer — the same role `RAW.Domain` would play, just under the name this repo already uses. |
| `RAW.Application` (CQRS use cases, submodules `ChangeRequests/Assessments/Scoring/Committee/Audit`) | `3-Service/Humaid.RiskGovernance.AdminUI.Services/<Module>/` | Same module boundaries, kept as sub-folders of the existing Services project rather than a new project. |
| `RAW.Infrastructure` (EF Core) | `4-Persistence/Humaid.RiskGovernance.AdminUI.DA` (Dapper, stored procedures only) | Explicit call: this repo's convention is Dapper against named `func_*`/`sp_*` routines, never an ORM or ad-hoc SQL. EF Core was not adopted. |
| `RAW.AI` (Claude orchestration, RAG, prompts) | New sibling project `3-Service/Humaid.RiskGovernance.AdminUI.AI` | Kept as CLAUDE.md suggested — a separate project from `.Services` so the AI-orchestration surface (prompts, Claude API client, citation-fabrication guards) has one clear owner and can be tested/replaced independently of business logic. |
| `RAW.Api` | `1-API/Humaid.RiskGovernance.AdminUI.Web` | Same role, existing project. |
| One monolithic `docs/architecture/` | This file | Records the decision so it isn't silently lost — matches CLAUDE.md's own `docs/architecture/` folder expectation. |

## Database structure

`src/4-Persistence/Humaid.RiskGovernance.AdminUI.DB/` — a plain SQL folder (schema, stored
functions, seed data), not a compiled project — is the schema's single source of truth. Every repo
method in `.DA` calls a named function from here; nothing issues ad-hoc SQL.

## Committee decision resolution rule (Epic 8/10)

CLAUDE.md flags this as an open question: *"Is committee decisioning by majority vote, unanimous
consent, or a designated chair's final call after discussion?"* Resolved for this MVP as a
**configurable quorum with a conservative deterministic rule**, implemented in
`CommitteeService.CastVoteAsync` and driven by the `CommitteeQuorum` workflow rule (Epic 10 -
`workflow_rule` table, default `{"quorum": 2}`, see `seed/seed_workflow_rules.sql`):

1. Wait until at least `quorum` votes are cast for the assessment.
2. Any single `Reject` present -> resolution is `Rejected` (conservative: one dissenting reject
   blocks approval, doesn't get outvoted).
3. Else, any `Defer` present -> resolution is `Deferred`.
4. Else, any `ApproveWithConditions` present -> resolution is `ApprovedWithConditions`, with every
   member's conditions text concatenated (nothing is dropped).
5. Else (all `Approve`) -> resolution is `Approved`.

This is a documented, stated decision (not an accident) and a clear extension point: swapping in
"unanimous consent" or "chair override" later only touches `CommitteeService`, not the schema.

## Audit design (see also `docs/governance/human-in-the-loop-gates.md`)

Every entity an AI output can populate (category mapping, extracted field, narrative section,
risk score) is modeled as a single current-state row, not a version chain. Instead, every stored
function that writes one of these rows does so in the same transaction as an `INSERT` into
`audit_event`, capturing the actor, before/after JSON, and (for any human edit or override) the
mandatory reason. `audit_event` itself has no update/delete function, and a database trigger
rejects `UPDATE`/`DELETE` against it outright — so "nothing is silently overwritten" is enforced
at the data layer, not just by application code choosing not to call a delete method (user-stories
US-9.2's explicit requirement).
