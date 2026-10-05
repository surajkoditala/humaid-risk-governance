# Review Rules

The checklist a human reviewer — or the automated [`dev_harness/`](dev_harness/) — checks every
change against. Automated findings inform the reviewer; they never replace one. No change merges
on automated approval alone.

## Human-in-the-Loop (process, not product)
- A human reviews and approves every change before it merges, regardless of how it was drafted.
- AI-drafted or AI-assisted commits should carry a `Co-Authored-By:` trailer identifying the tool,
  so authorship stays traceable in `git log`/`git blame`.
- "The AI suggested it" is not a justification during review.
- This is about how *this repo's own code* gets written — it is separate from the product's own
  human-in-the-loop gates for AI-generated *data* (categories, extracted fields, narratives),
  which are covered below and in `docs/governance/human-in-the-loop-gates.md`.

## Architecture
- 4-layer Clean Architecture respected: `1-API → 2-Infrastructure → 3-Service → 4-Persistence`,
  outer depends on inner, never reverse.
- Interfaces declared in `2-Infrastructure` only; implementations in `3-Service`/`4-Persistence`.
- No business logic in controllers; no persistence logic in controllers or services.

## Database
- Schema/behavior changes are made in the SQL project's function/table definitions
  (`src/4-Persistence/Humaid.RiskGovernance.AdminUI.DB/`), not by hand-editing a generated deploy
  script.
- Every override of an AI-generated or calculated value: method signature takes a mandatory
  `reason`; the underlying `func_` writes an `audit_event` row in the same transaction.
- A new human-override path added to a service/controller without a matching entry in
  `docs/governance/human-in-the-loop-gates.md` should be flagged.

## AI Clients / Citation Guard
- Any new or modified AI client output is grounded: nothing outside the supplied
  categories/facts/policy excerpts is returned unflagged (dropped, or flagged
  `needsReview`/`unsupportedClaims`, depending on which client).
- If a `SystemPrompt` constant changes, the mirrored file in `ai/prompts/*.md` changes too, and
  vice versa.
- A new deterministic-by-design area (search, scoring) suddenly calling `IChatCompletionClient` is
  a smell worth a second look, not an automatic fail — flag it for discussion.
- New AI-adjacent config fails loudly if missing; no hardcoded model ID/deployment value.

## Async Standards (C#)
- No `.Result` or `.Wait()`.
- `CancellationToken` accepted and forwarded through service/persistence calls.

## Comments & Readability
- Code is readable by any engineer on the team, not just its author.
- Non-obvious algorithms, ordering dependencies, or workarounds have a comment explaining *why*.
- A complex change is not left uncommented because it "seemed obvious" while writing it.

## Frontend (webapp changes)
- No inline `fetch` bypassing the existing API-client layer.
- Auth0 (`useAuth0`) remains the single source of auth state/token — no parallel token storage.

## Python (LangGraph service changes)
- New/changed graph nodes have an explicit failure path for unparseable model output.
- The same citation-guard rule as the mirrored C# client is applied before returning a proposal.
- Config failures are loud (`RuntimeError` with a specific message), not silent defaults.

## Testing
- New business logic (service methods, graph nodes) has test coverage for both the success path
  and the failure/guard path (e.g., "model returns an out-of-allow-list category" is itself a test
  case, not just the happy path).
- External dependencies (AI clients, HTTP calls) are mocked in unit tests.

## Review Output
For every finding, provide:
1. Severity (Critical / High / Medium / Low)
2. File
3. Line number (if known)
4. Rule violated
5. Recommendation

Critical and High findings should block completion until resolved or explicitly accepted by a
human reviewer with a stated reason.
