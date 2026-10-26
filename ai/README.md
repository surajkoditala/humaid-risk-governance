# AI orchestration

This folder documents the AI harness for the Risk Assessment Workbench — where it's used, how
each call is grounded, and how the "system prepares, humans decide" rule is enforced in code (see
`docs/governance/human-in-the-loop-gates.md` for the full traceability table).

## Where AI is used, and where it deliberately isn't

| Epic | AI call? | Client | Why |
|---|---|---|---|
| 2 — Category Mapping | Yes | `CategoryMappingAiClient` | Proposing which named framework categories apply is a judgment call over free text (title/description) — a real fit for an LLM, grounded against a fixed category list so it can't invent one. |
| 3 — Policy Research | **No** | — (`func_searchPolicyChunks`, Postgres full-text search) | Ranking indexed text by keyword relevance is a solved, deterministic search problem. Spending an LLM call on it would add latency, cost, and nondeterminism for no accuracy gain — a deliberate "when NOT to use an LLM" choice. |
| 4 — Document Extraction | Yes | `DocumentExtractionAiClient` | Pulling structured facts out of free-text document content is exactly what an LLM is good at; each field carries a confidence score and `needsReview` flag rather than a silent guess. |
| 5 — Narrative Drafting | Yes | `NarrativeDraftingAiClient` | Synthesizing a professional narrative from mapped categories, relied-upon policy, and extracted facts is generative, not lookup — but it is only allowed to cite what it was actually given (see "citation guard" below). |
| 7 — Scoring | **No** | — (`ScoringService.CalculateAsync`) | `Residual = Inherent − (Effectiveness × Mitigation)` is a fixed formula with a hard mathematical guarantee (residual can never reach zero) — introducing an LLM here would trade a provable guarantee for a probabilistic one. |

## Citation-fabrication guard (all three AI clients)

Every AI client is grounded against a fixed, supplied set of facts/categories/policy excerpts, and
every client **drops or flags what it can't trace back to that input** rather than passing it
through:

- `CategoryMappingAiClient` discards any proposed category whose ID isn't in the supplied allowed
  list (see `ProposeAsync` in `src/3-Service/Humaid.RiskGovernance.AdminUI.AI/CategoryMappingAiClient.cs`).
- `DocumentExtractionAiClient` requires a `sourceExcerpt` for each field and forces `needsReview` on
  anything the model itself flagged low-confidence.
- `NarrativeDraftingAiClient` requires unsupported statements to be returned separately in
  `unsupportedClaims`, never folded into the narrative text (`assessment_narrative_section.unsupported_claim_flags`).

## Client, model, prompts

All three AI clients depend on `IChatCompletionClient`
(`src/2-Infrastructure/.../Interfaces/Ai/IChatCompletionClient.cs`), not a concrete provider —
`Program.cs` decides which implementation they actually get, via `AI_PROVIDER`:

| `AI_PROVIDER` | Implementation | When |
|---|---|---|
| `Anthropic` (default) | `ClaudeApiClient` — thin wrapper over Anthropic's Messages API, no SDK dependency | Local dev today; works as soon as `ANTHROPIC_API_KEY` + `ANTHROPIC_MODEL` are set |
| `AzureFoundry` | `AzureFoundryChatCompletionClient` — thin wrapper over the Azure AI Foundry Model Inference API | The team's agreed target (2026-09-09 architecture sync) — keeps every model call inside Azure. Needs `FOUNDRY_PROJECT_ENDPOINT` + `FOUNDRY_API_KEY` + `FOUNDRY_MODEL_DEPLOYMENT` once DevOps provisions the Foundry project; Terraform provisions the Container Apps environment/registry only, the Foundry project itself is set up via the Azure Portal, not IaC |

Both providers are required config (no hardcoded model ID/deployment name for either — check the
current model list rather than trusting a value baked in months ago); missing config fails loudly
the first time an AI endpoint is called, matching every other AI touchpoint's "flag explicitly,
don't silently guess" rule. Switching providers touches zero prompt or parsing code — the three
AI-touchpoint clients (`CategoryMappingAiClient` etc.) only ever see `IChatCompletionClient`.

Prompts live as C# string constants next to each client (so the running app has no file-path
dependency) and are mirrored below for review/audit — if you change one, change both:

- [`prompts/category-mapping.md`](prompts/category-mapping.md) ↔ `CategoryMappingAiClient.SystemPrompt`
- [`prompts/document-extraction.md`](prompts/document-extraction.md) ↔ `DocumentExtractionAiClient.SystemPrompt`
- [`prompts/narrative-drafting.md`](prompts/narrative-drafting.md) ↔ `NarrativeDraftingAiClient.SystemPrompt`

## Measured token use

Both provider clients record the token counts the provider reports for every successful call
(`AiUsageTelemetry` in `src/3-Service/.../AI`) — exact figures, nothing estimated locally. Each
touchpoint client tags its calls with its step (`category_mapping`, `document_extraction`,
`narrative_drafting`) through an ambient scope, so the provider clients and `IChatCompletionClient`
keep their signatures. A failed call (401, 404, 5xx) carries no usage and records nothing; a count
the provider did not report is skipped, never recorded as zero.

- **Metric:** `gen_ai.client.token.usage` (OpenTelemetry GenAI semantic-convention name), meter
  `Humaid.RiskGovernance.AI`, one measurement per token type: `input`, `output`, and for Anthropic
  `cache_read` / `cache_creation`. Dimensions: `gen_ai.system` (`anthropic`, `az.ai.inference`),
  `gen_ai.request.model`, `humaid.ai.operation`.
- **Where it lands:** `Program.cs` registers the meter with the Azure Monitor exporter, so with
  `APPLICATIONINSIGHTS_CONNECTION_STRING` set it appears in the Log Analytics `AppMetrics` table. Tokens
  per step and model:

  ```kusto
  AppMetrics
  | where Name == "gen_ai.client.token.usage"
  | extend TokenType = tostring(Properties["gen_ai.token.type"]),
           Step = tostring(Properties["humaid.ai.operation"]),
           Model = tostring(Properties["gen_ai.request.model"])
  | summarize Tokens = sum(Sum) by Step, Model, TokenType
  ```

- **Also logged:** one `AI usage: ...` line per call (visible in the container logs and `AppTraces`).
- **Not (yet) recorded:** tokens per change request / assessment — that needs the request id carried
  into the AI clients and a table to hold it. The metric answers "how many tokens does each step use";
  it does not yet answer "what did this one assessment cost".

## See also

- [`docs/architecture/langgraph-evaluation.md`](../docs/architecture/langgraph-evaluation.md) — whether an orchestration framework (LangGraph) should replace the harness described above, and why the current recommendation is no (proposal, pending team decision).
- [`docs/architecture/langgraph-integration.md`](../docs/architecture/langgraph-integration.md) — how `ai/langgraph/`'s standalone Python service (an alternate *implementation* behind the same interfaces, not a replacement for them) ties into the Workbench today.
- [`harness/README.md`](../harness/README.md) — unrelated to the above: this repo's own *development-process* rules and standards (coding conventions, review checklist, and a local dev-tooling LangGraph CLI that checks a diff against them). Governs how this repo's code gets written, not how the product's AI touchpoints behave at runtime.
- [`docs/architecture/dev-harness.md`](../docs/architecture/dev-harness.md) — diagrammed architecture of that dev-tooling LangGraph CLI (node flow, module layout, how it borrows `ai/langgraph/`'s provider config without depending on it).
