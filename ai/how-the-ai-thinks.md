# How the AI "thinks" in the Risk Workbench

Plain-language answer to: *what does "Propose with AI" actually send, and how does it know the FFIEC
categories?* Sources: `ai/prompts/*.md`, which mirror the `*AiClient.SystemPrompt` constants in
`src/3-Service/Humaid.RiskGovernance.AdminUI.AI/`, and the LangGraph service in `ai/langgraph/`.

## The short answer

The model is **not trusted to know FFIEC**. The application supplies the FFIEC categories in every request,
and the model may only choose from that list.

1. The four FFIEC BSA/AML categories (Products & Services, Customers & Entities, Geographic Locations,
   Delivery Channels) are **seeded in the database** (`seed/seed_ffiec_framework.sql`).
2. For a request, `func_getChangeTypeCategoryDefaults` returns the categories that apply to that change type,
   each with its code, name, citation section and weight (Primary / Secondary).
3. That list is put **into the prompt** as JSON, next to the change's title and description.
4. The model returns proposals as JSON. Any `riskCategoryId` that is **not in the supplied list is dropped**
   in code before anything is saved. The model cannot cause an invented category or citation to be stored.

## The three AI touchpoints

| Step | Input the model receives | What it must return | Guard in code |
|---|---|---|---|
| Category mapping (Epic 2) | Change type, title, description, allowed categories (JSON) | JSON array of `{riskCategoryId, rationale}` | IDs outside the allowed list are dropped |
| Document extraction (Epic 4) | Change type, the text extracted from the uploaded document | JSON array of `{fieldKey, fieldValue, confidence, needsReview, sourceExcerpt}` | Only facts stated in the text; unsure values must set `needsReview: true` |
| Narrative drafting (Epic 5) | Change details, category + citation, policy excerpts the analyst marked "rely on", extracted facts | JSON `{narrativeText, unsupportedClaims[]}` | Claims without a supplied source go to `unsupportedClaims`, never into the narrative |

Not AI at all: **policy search** (Postgres full-text search) and **scoring** (a deterministic formula).

## Rules every prompt shares

- Cite only what was supplied. Never invent a citation, fact, or source.
- Respond with JSON only, so the output is machine-checked rather than read as free text.
- When unsure, say so (`needsReview`, `unsupportedClaims`) instead of guessing.
- The output is always saved as *AI-drafted* and needs a human action before the flow can move on.

## Where the human steps in

Every AI output has a matching gate: the analyst adds or overrides categories, corrects extracted fields,
and reviews or edits each narrative section. Any edit needs a stated reason, and both original and edited
values are kept. See `docs/governance/human-in-the-loop-gates.md`.

## Failure behaviour

An AI outage must never block the user. If the model is unavailable, or returns something that is not valid
JSON, the app falls back to **no proposals** and the analyst does the step manually. The LangGraph category
graph does the same: invalid JSON gives an empty list, never a guess.

## The LangGraph alternative (`ai/langgraph/`)

A separate Python service that can be swapped in for the C# clients without changing their interfaces. Today
only category mapping is implemented, as a single `propose` node followed by the allow-list filter. Model
choice is set by `LLM_PROVIDER` (gemini or anthropic). Planned next: encode FFIEC rules and criteria as
their own graph nodes, and add the document-extraction and narrative-drafting graphs.

## Open questions this leaves for the team

- What exactly is the "policy corpus", and what happens in the background when an analyst searches it?
  (Shanthi) Answer to confirm with Suleman: a synthetic library of internal policies and prior assessments,
  seeded in `schema/007_policy_corpus.sql`, searched with Postgres full-text search.
- Which real document does a product owner upload? (Shanthi to define.)
- Test AI output against sample categories (`evals/`) to check it makes sense.
