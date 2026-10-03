# Code Review Checklist

Review the current diff (or the provided files) against `harness/review-rules.md`. Report every
violation as a numbered finding with file, line (if known), rule, and a suggested fix. This is the
same checklist `harness/dev_harness/` runs automatically — use this file directly when you want a
manual, conversational review instead of the CLI.

## Architecture
- [ ] 4-layer boundaries respected — `1-API → 2-Infrastructure → 3-Service → 4-Persistence`
- [ ] Interfaces declared in `2-Infrastructure` only; implementations in `3-Service`/`4-Persistence`
- [ ] No business logic in controllers; no persistence logic in controllers or services

## Database
- [ ] Schema/behavior changes made in the SQL project's function/table definitions, not a
      hand-edited generated deploy script
- [ ] Any new override of an AI-generated/calculated value takes a mandatory `reason` and the
      underlying `func_` writes `audit_event` in the same transaction
- [ ] A new human-override path has a matching entry in `docs/governance/human-in-the-loop-gates.md`

## AI Clients / Citation Guard
- [ ] New/changed AI client output drops or flags anything not traceable to its supplied input
- [ ] `SystemPrompt` constant changes are mirrored in `ai/prompts/*.md` (and vice versa)
- [ ] A deterministic-by-design area suddenly calling `IChatCompletionClient` is flagged for
      discussion, not silently accepted
- [ ] New AI-adjacent config fails loudly if missing; no hardcoded model ID/deployment value

## Async Standards (C#)
- [ ] No `.Result` or `.Wait()`
- [ ] `CancellationToken` accepted and forwarded through service/persistence calls

## Comments & Readability
- [ ] Non-obvious algorithms, ordering dependencies, or workarounds have a "why" comment
- [ ] No complex change left uncommented because it "seemed obvious" while writing it

## Frontend (webapp changes)
- [ ] No inline `fetch` bypassing the existing API-client layer
- [ ] Auth0 (`useAuth0`) remains the single source of auth state/token

## Python (LangGraph service changes)
- [ ] New/changed graph nodes have an explicit failure path for unparseable model output
- [ ] The same citation-guard rule as the mirrored C# client is applied
- [ ] Config failures are loud (`RuntimeError` with a specific message)

## Testing
- [ ] New business logic has both success-path and failure/guard-path test coverage
- [ ] External dependencies (AI clients, HTTP) are mocked in unit tests

## Human-in-the-Loop (process)
- [ ] AI-drafted/AI-assisted commits carry a `Co-Authored-By:` trailer
- [ ] No secrets or real customer-shaped data pasted into this conversation

## Output format
For every finding: severity, file, line (if known), rule violated, recommendation. Critical/High
findings should block completion until resolved or explicitly accepted with a stated reason.
