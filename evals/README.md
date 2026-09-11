# Evaluation framework

How we know an AI touchpoint's output is good, not just that it ran without throwing. Covers the
three real-LLM clients — `CategoryMappingAiClient` (US-2.1), `DocumentExtractionAiClient` (US-4.1),
`NarrativeDraftingAiClient` (US-5.1/5.2) — the same production code in
`src/3-Service/Humaid.RiskGovernance.AdminUI.AI`, referenced directly by
`Humaid.RiskGovernance.AdminUI.Evals` rather than reimplemented. Policy Research and Scoring aren't
here because they're deterministic, not AI (see `ai/README.md`'s table) — nothing to evaluate for
"is the model's judgement good" when there's no model in the loop.

## Run it

```powershell
$env:AI_PROVIDER = "Anthropic"          # or "AzureFoundry"
$env:ANTHROPIC_API_KEY = "..."
$env:ANTHROPIC_MODEL = "..."
dotnet run --project evals/Humaid.RiskGovernance.AdminUI.Evals
```

No API key configured? The two deterministic cases (see below) still run and pass; every
AI-calling case reports `Skip` rather than `Fail` - a missing key is not the same claim as "the
model got it wrong," and the report says so explicitly. A results table prints to the console and
a timestamped Markdown report lands in `evals/results/` (gitignored - these are run artifacts, not
fixtures).

## Methodology

Fixed input scenarios per touchpoint (`evals/datasets/*.json`), each scored against a rubric that
is **deterministic wherever the domain allows it** — never a second LLM grading the first one's
homework without saying so plainly when that's what's actually happening (it isn't, here).

| Suite | Scoring | Why this is a legitimate deterministic check |
|---|---|---|
| Category mapping | Set-overlap against expected FFIEC category codes, plus a check that nothing outside the case's own `allowedCategories` was proposed | Categories are a small, fixed, enumerable set (the same grounding list the production code itself passes to the model) - exact-match scoring is not an approximation here, it's the actual correctness criterion US-2.1 AC3 states |
| Document extraction | Exact/substring match on mandated field values; explicit checks that ambiguous source text gets `needsReview: true` and that unambiguous text does not | Field values and the needsReview flag are concrete, checkable facts against the supplied source text |
| Narrative drafting | **Heuristic proxy only** - citation/keyword presence, well-formedness, and (for regeneration) whether feedback visibly changed the output | Narrative *quality* is not independently verifiable without a human or a second judge model - see below |

## What narrative scoring does NOT verify

Read this before trusting a green narrative result for more than it's worth. The `well_formed`
check (`nr-02` in `narrative.json`) confirms the model returned a non-empty, parseable response -
nothing more. It does **not** independently verify the model avoided fabricating a claim beyond
what it was given; that property is a prompt-level instruction
(`ai/prompts/narrative-drafting.md`: "never invent a citation, a fact, or a source not supplied to
you") enforced by `NarrativeDraftingAiClient`'s contract (unsupported claims go in
`unsupportedClaims`, not the narrative text) and, ultimately, by the human analyst review gate
downstream (US-6.3) - not by this eval. Stating this limitation plainly is itself the point: a
narrative eval that quietly claimed more than it checks would be worse than no eval at all.

## Two deterministic, zero-cost cases (no AI call, ever)

`cm-05-no-framework-mapping` (empty `allowedCategories`) and `de-04-empty-document` (blank
`documentText`) exercise `CategoryMappingAiClient`/`DocumentExtractionAiClient`'s own early-return
guard clauses - US-2.1 AC3 and the empty-input case respectively. These run and must pass
regardless of `AI_PROVIDER` configuration; if either fails, the regression is in application code,
not model behavior.

## Extending this

Add a case to the relevant `datasets/*.json` file - no code change needed unless it's a genuinely
new `checkType` for narrative. Prefer adding edge cases (ambiguous input, no-mapping scenarios,
conflicting facts) over more golden-path cases; the golden path is already covered and rarely where
regressions hide.
