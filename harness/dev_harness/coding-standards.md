# Coding Standards

Conventions for this repo, across its three codebases. These are **descriptive of the standard we
want**, not all already universally applied — existing files that predate this document are not
retroactively "wrong," but new code should follow this.

---

## C# (`src/`, `evals/`)

### General
- Target current C# language features (primary constructors, collection expressions `[]`,
  pattern matching) where they improve clarity — don't force a feature where a simple form reads
  better.
- `async`/`await` throughout — never `.Result` or `.Wait()`. Always accept and forward
  `CancellationToken` through service and persistence layers.
- Use `var` when the right-hand type is obvious from the expression.
- Nullable reference types are enabled — don't suppress warnings with `!` without a comment
  explaining why the null-forgiveness is actually safe at that call site.

### Naming
- Interfaces: `I` prefix, declared in `2-Infrastructure` — e.g. `ICategoryMappingAiClient`.
- Implementations live in the layer that matches their responsibility: `3-Service` for business
  logic/orchestration, `4-Persistence` for Dapper repos and external API clients.
- Repos suffix with `Repo`, external API clients suffix with `Client`.

### File header
A one-line `/// <summary>` doc comment is expected on every public class that isn't
self-explanatory from its name alone (see `CategoryMappingAiClient.cs` for the existing style —
a summary that states the epic/user-story it implements and where its mirrored prompt file
lives). A full copyright banner is not this repo's convention and should not be added.

### Comments
- Comments explain **why**, not what. The existing codebase already does this well — see
  `CategoryMappingAiClient.ProposeAsync`'s comments on the empty-defaults guard and the optional
  external-context grounding. New code should match that density, not add noise.
- Any non-obvious guard, ordering dependency, or "looks wrong but isn't" line needs a comment.

### Architecture — 4-layer Clean Architecture
Outer layers depend on inner layers, never the reverse:

```
1-API            → Controllers, Program.cs, request/response wiring
2-Infrastructure → Interfaces, Models, Enums, Options (no implementations)
3-Service        → Business logic implementing interfaces from 2-Infrastructure
4-Persistence    → Dapper repos (stored-function calls), external API clients (AI, Mock Systems)
```

- No business logic in controllers.
- No persistence/repo logic in controllers or services directly — go through the repo interface.
- AI clients live in `3-Service` (treated as orchestration/business logic, since they call out to
  an external model and apply the citation guard), not `4-Persistence`.

### Database access — stored functions, not an ORM
This repo's source of truth for schema **and** data access is the SQL project under
`src/4-Persistence/Humaid.RiskGovernance.AdminUI.DB/` — functions prefixed `func_`, called via
Dapper. There is no EF Core, no code-first migrations, no `DbContext`.

- A schema or behavior change starts in the `.sql` function/table definition in the DB project,
  not in a C# entity.
- Every `func_` that performs a human override of an AI-generated or calculated value must write
  an `audit_event` row in the same transaction as the state change (see the `reason` + override
  pattern below).
- Deploy scripts are generated from the DB project — don't hand-edit a generated deploy script.

### The `reason` + `audit_event` override pattern
This is this repo's load-bearing convention — every place a human overrides an AI-generated or
calculated field follows the same shape:

```csharp
Task OverrideAsync(Guid id, string newValue, string reason, CancellationToken cancellationToken);
```

- The method signature always takes a `reason` parameter; the API layer returns 400 if it's blank.
- The underlying stored function always writes an `audit_event` row recording the original and new
  value, in the same transaction as the state change.
- See `docs/governance/human-in-the-loop-gates.md` for the full table of where this applies.

### AI clients — the citation-fabrication guard
Every client that calls `IChatCompletionClient` (`CategoryMappingAiClient`,
`DocumentExtractionAiClient`, `NarrativeDraftingAiClient`) must drop or flag anything the model
returns that cannot be traced back to the fixed input it was given — never pass an invented
category ID, an un-sourced extracted field, or an unsupported narrative claim through unflagged.
See `ai/README.md`'s "Citation-fabrication guard" section for the exact rule per client.

### Prompts
Prompts live as C# string constants next to their client (`SystemPrompt` in
`CategoryMappingAiClient.cs` etc.), mirrored as markdown in `ai/prompts/*.md` for review. If you
change one, change both.

### Config
- New AI-adjacent or external-integration config must fail loudly (throw with a clear message) on
  first use if missing — never silently default to a guess. This matches the existing
  `AI_PROVIDER` / `ANTHROPIC_API_KEY` pattern.
- Don't hardcode a model ID, deployment name, or endpoint — check the current value is actually
  configured rather than relying on one baked in months ago.

---

## React / TypeScript (`webapp/`)

- Function components with hooks — no class components.
- Co-locate a component's styles/logic; shared UI primitives live under the existing
  `@base-ui/react` + `class-variance-authority` pattern already used in this app — don't introduce
  a second component-variant system.
- Auth0 state (`useAuth0`) is the only source of the current user/token — don't duplicate token
  storage elsewhere.
- No inline `fetch` calls scattered across components — route API calls through this app's
  existing API-client layer (match the pattern already used for `/api/User/Me` etc.), so auth
  headers and the base URL stay centralized.
- Prefer the platform/Vite defaults (ESM, `type: "module"`) already configured in
  `webapp/package.json` — don't add a bundler-specific escape hatch without a strong reason.

---

## Python (`ai/langgraph/`)

- Every public function gets a type-annotated signature; this repo already does this
  consistently (see `app/llm.py`, `app/graphs/category_mapping.py`) — keep it up.
- Fail loudly on missing config (`RuntimeError` with a specific message), matching the C# side's
  `AI_PROVIDER` convention — see `get_chat_model()`.
- Any LangGraph node that parses model output must have an explicit failure path (invalid JSON →
  empty/safe result, never an uncaught exception bubbling to the caller) and must apply the same
  allow-list/citation-guard rule as the equivalent C# client it mirrors.
- New graphs go in `app/graphs/`, one file per touchpoint, following `category_mapping.py`'s
  shape: `_State` TypedDict → node function(s) → `_graph` → a single `run_*` entrypoint function
  that `app/main.py` calls. Don't let `main.py` touch `StateGraph` internals directly.
