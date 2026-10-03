# Presentation Script — Architecture & Flow Overview

Narration to read aloud while sharing/scrolling through
[`presentation-tech-architecture-overview.md`](presentation-tech-architecture-overview.md). Each
`[SHOW: ...]` cue marks where to scroll to or point at that document; the text under it is what to
say. Written for a live, spoken delivery — plain sentences, no jargon dumps. Roughly 4-5 minutes
read at a normal pace; trim the bracketed "if there's time" asides to fit a shorter slot.

---

### Opening

**[SHOW: top of the document, before scrolling to any diagram]**

> We built the Risk Assessment Workbench — a system that carries a proposed business change, at a
> bank, from the moment someone raises it, through an assessment, to a final committee decision.
> Today at a real bank this runs on email, Word docs, and SharePoint, and takes fifteen to twenty
> business days. What we're showing you answers two questions in order: who uses this and what does
> it talk to, and how does a single request flow through the system end to end.
>
> One rule sits behind everything you're about to see: **the system prepares, humans decide.**
> Nothing in this application auto-approves or auto-rejects anything. You'll see that rule show up
> structurally, not just as a slide bullet.

---

### Tech stack, before the diagrams

**[SHOW: Tech Stack at a Glance diagram]**

> Quickly, before the diagrams — what this is actually built with. The frontend is a React
> single-page app. The backend is ASP.NET Core on .NET 10, talking to PostgreSQL — no ORM, we use
> Dapper directly against named database functions, so every query is explicit and reviewable.
> Identity and login go through Auth0. Uploaded documents go to blob storage. And the three places
> we actually call an AI model all go through Anthropic's Claude API today, behind an abstraction
> that could swap in another provider without touching the calling code. Everything runs in Docker
> locally and as Azure Container Apps in the cloud — same images, both places.

---

### 1. System Context

**[SHOW: Section 1, System Context Diagram]**

> This is the widest possible zoom-out. Four kinds of people use this system: a Product Owner, who
> raises the change; an FCRM Analyst, who does the assessment; the Risk Committee, who votes on the
> outcome; and an Admin, who manages who has access. Everything they do goes through the one box in
> the middle — the Workbench.
>
> Outside that box are three things we don't own the way we own the Workbench. Auth0 handles login
> and issues the tokens that prove who you are on every single request — nobody's role is ever just
> trusted from a request itself. Anthropic's Claude API is where the AI-assisted parts of the
> workflow actually happen. And this box here — Mock External Systems — stands in for the bank's
> real CRM, core banking, and vendor management systems. It's code we wrote ourselves, but we built
> it as its own separate service on purpose, because in a real deployment this would be systems the
> bank already has, not something we own.
>
> [If there's time: notice there's no line from the AI box straight to a decision anywhere. That's
> deliberate, and you'll see exactly why in the next diagram.]

---

### 2. The intake → audit workflow

**[SHOW: Section 2, the flowchart]**

> This is the one that matters most, because it's the actual life of a request, and it's where the
> "system prepares, humans decide" rule becomes visible instead of just stated. Look at the color
> coding: purple is AI, blue is deterministic — meaning plain code, no model involved — and green is
> a human decision point.
>
> A Product Owner submits a request. It picks up context from those Mock Systems — the customer,
> the product, the vendor involved — and that gets locked into an immutable snapshot right away, so
> what the assessment is based on can never quietly change underneath it later.
>
> Only three steps in this whole flow are actually AI: mapping the request to risk categories,
> pulling structured data out of an uploaded document, and drafting the narrative for a human to
> read. And notice the category mapping step is grounded — it's citing an actual section of the real
> FFIEC BSA/AML Examination Manual, not inventing a category. That's a real published framework, not
> something we made up.
>
> Policy research and the actual risk scoring are both blue — deterministic. Policy research is
> plain Postgres full-text search, not a model call. And scoring is a fixed formula: inherent risk
> minus how much the controls mitigate it, and there's a hard rule, enforced at the database level
> and in code, that residual risk can never hit zero. Controls reduce risk, they don't eliminate it.
>
> Then it hits green — an FCRM Analyst has to review, and can edit or override anything, but always
> has to give a reason. Only after that does it go to the Risk Committee, who vote individually, and
> a quorum-based rule decides the outcome — and if anyone votes reject, that's conservative by
> design: one reject wins over any number of approvals.
>
> And every single one of those steps — the AI outputs, every edit, every vote, the final decision —
> writes to an audit trail that cannot be edited or deleted. That's not just an app-level rule, it's
> enforced by a database trigger. So if an examiner ever needs to reconstruct why a decision was
> made, that record already exists and can't have been quietly changed.

---

### Closing

**[SHOW: back to the top, or wherever the next agenda item is]**

> So, in one sentence: three real user roles, one system, three places AI actually gets involved —
> always with a human reviewing before it moves forward — and everything that happens along the way
> is written to a trail nobody, including us, can edit after the fact.

---

## Presenter notes

- If asked "why not use an ORM": one line is enough — Dapper against named, reviewable database
  functions was already the repo's convention before this project started; it wasn't changed to fit
  the hackathon brief.
- If asked "what happens if the AI is down": the manual path always works — an AI outage never
  blocks a user from finishing an assessment by hand.
- If asked about Azure AI Foundry: it's supported in code as a swappable provider, but not
  provisioned yet — Anthropic is what's actually running today.
- Don't get pulled into the database schema here — that's a different, much longer conversation;
  point to [`db-schema-diagram.md`](db-schema-diagram.md) if someone really wants it.
