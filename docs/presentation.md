# Genius Hacks Q3 - Mentor Call Presentation (Vijay Venkatesh)

**When:** 12:00 noon CST, 30 min. **Dry run:** 9:30 CST. **Format:** no slides, one person shares the screen from this page.
**Timing:** overview about 5-10 min, the rest for discussion and Q&A.

| # | Section | Presenter | Time |
|---|---|---|---|
| 1 | Context | Suraj | 1-2 min |
| 2 | Requirements | Shanthi | 2-3 min |
| 3 | Architecture | Francis | 2 min |
| 4 | App demo | Suleman | 3-4 min |
| 5 | Pipelines | Suraj | 1-2 min |
| 6 | Q&A / discussion | All | remainder |

Links to open live: microsite, ADO board, GitHub repo, pipelines, running app (all in the meeting chat).

---

## 1. Context (Suraj)

- The problem: a bank's FCRM team must assess the financial-crime risk of every proposed business change, and today it is slow and manual.
- What we built: the **Risk Assessment Workbench**. The system prepares, humans decide. Nothing is auto-approved or auto-rejected.
- Stack: React SPA, ASP.NET Core (.NET 10), PostgreSQL, Auth0, Azure Blob, AI behind an abstraction (Anthropic / Azure Foundry, LangGraph + Gemini in progress).

## 2. Requirements (Shanthi)

Cover: how the vague problem was expanded, the assumptions made, why the FFIEC BSA/AML framework was chosen, how AI was used. Show that this produced **11 epics** (do not walk through stories). Source: `docs/requirements/user-stories.md`.

Notes to add at the dry run: _(Shanthi)_

## 3. Architecture (Francis)

Use the ecosystem diagram: [`docs/architecture/ecosystem-diagram.md`](docs/architecture/ecosystem-diagram.md), section 4b (human-in-the-loop gates). Simpler yes/no version if the room prefers it: [`docs/architecture/presentation-flowchart.md`](docs/architecture/presentation-flowchart.md).

Say:
- Only **three** steps call an AI model: category mapping, document extraction, narrative drafting. Policy search and scoring are deterministic.
- Seven human gates sit between AI output and the committee. Every edit needs a reason and both values are kept.
- **An AI outage never blocks the user.** The manual path always works.
- Immutable audit trail: a database trigger rejects UPDATE/DELETE.
- Do not show the DB schema.

How the AI works, in plain language: [`ai/how-the-ai-thinks.md`](ai/how-the-ai-thinks.md).

## 4. App demo (Suleman)

Use the requests already configured end to end (for example request #2), not new ones.

1. **Login:** Auth0 replaces the old role dropdown. Roles: Admin, Product Owner, Analyst, Committee Member. Menu shows only the screens for the user's roles.
2. **Admin:** Users screen (manage users and roles), Configuration (quorum, default 2).
3. **Category mapping:** Customer & Entity, Delivery Channel, Geography, Products & Services. AI proposes; analyst can add or override with a reason.
4. **Policy:** full-text search; each result marked "rely on" or "not relevant".
5. **Extraction:** values from the uploaded PDF/DOC/XLSX, each shown as AI-extracted or analyst-corrected (with reason).
6. **Narrative:** AI-generated; analyst regenerates, edits or replaces (with reason), marks "analyst reviewed".
7. **Scoring:** out of 5; finalize allowed when the average is above 2.5.
8. **Committee:** Approve / Approve with conditions / Defer / Reject, reasons required. Quorum reached, request locks read-only, Product Owner sees the outcome.

Do not dwell on bugs. Talk about **how issues came up and how they were handled**, since that is what is scored.

## 5. Pipelines (Suraj)

Source: [`.azure-pipelines/README.md`](.azure-pipelines/README.md). Show the workbench and mock-api pipelines and the AI review step.

## 6. Talking points for Q&A

- **AI blocker and fallback:** Azure Foundry is the fallback; LangGraph on Gemini is in progress. AI is nice-to-have, manual always works.
- **DB migrations:** EF Core auto-migrations are on `release/1.00`; no manual SQL script.
- **Open questions we are closing:** what "policy corpus" means, what happens in the background on search, what a product owner really uploads.

## Open items after the call

- "Why is this step disabled" messages for locked steps.
- Remove developer text from screens.
- Grids: filters, sortable columns, server-side pagination.
- Add Suraj to Auth0 (shared with ERC).
