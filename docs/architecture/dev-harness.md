# Dev Harness — LangGraph Architecture & Flow

**Location of the tool itself:** `harness/dev_harness/`
**Status:** Working locally; informational CI pipeline in `.azure-pipelines/harness/dev-harness.yml` (ADO pipeline `gh-dev-harness`, runs on PRs to `release/1.00` and manually, posts its report on the PR)
**Related:** [`harness/README.md`](../../harness/README.md) · [`dev_harness/review-rules.md`](../../harness/dev_harness/review-rules.md) · [`langgraph-integration.md`](langgraph-integration.md) (the *product* LangGraph service — unrelated at runtime) · [`langgraph-evaluation.md`](langgraph-evaluation.md)

---

## 1. What this document covers

This document explains the **dev harness** — a separate, small LangGraph graph that reviews a local `git diff` against this repo's own coding/review standards before you commit. It is development tooling only:

- It is **not** called by the deployed Risk Assessment Workbench.
- It is **not** the same thing as `ai/langgraph/`'s product graphs (Category Mapping, Document Extraction, Narrative Drafting) — it just happens to reuse the same `get_chat_model()` function and the same local `.env` for convenience.
- It exists because this repo previously had **no automated linting or standards enforcement at all** — no `.editorconfig`, no ESLint config, no review checklist. This closes that gap for local development.

---

## 2. Why this is a LangGraph graph and not a single prompt

- Each "check" (architecture layering, database gate pattern, citation guard, etc.) is a **separate, narrowly-scoped concern**.
- A single large prompt asking a model to check everything at once tends to miss things or blend concerns together.
- LangGraph lets each concern be its **own node**, with its own short, focused instruction, run independently against the same diff.
- This mirrors the same design principle already used in the product's `category_mapping.py` graph: narrow role-scoped prompts beat one general-purpose prompt.

---

## 3. High-level flow

```mermaid
flowchart TB
    A["Developer runs:<br/>python -m dev_harness check"] --> B["diff_source.py<br/>git diff HEAD (or --since ref)"]
    B --> C["rules.py<br/>loads dev_harness/review-rules.md"]
    C --> D["graph.py<br/>builds initial state:<br/>diff + rules + empty findings"]
    D --> E["LangGraph StateGraph<br/>(fan-out, see section 4)"]
    E --> F["compile_report node<br/>merges all findings"]
    F --> G["Markdown report<br/>printed to terminal<br/>+ optional --out file"]
    G --> H["Human reviews report<br/>(nothing is auto-fixed<br/>or auto-committed)"]
```

- **Nothing is auto-applied.** The harness only ever produces a report. This matches the project's broader "system prepares, humans decide" philosophy — applied here to the *development process* itself, not just product data.
- **Grounded input only.** Each node only ever sees the diff and the rules text — never the whole repository — the same grounding discipline used by the product's AI clients (citation-fabrication guard).

---

## 4. The graph itself — fan-out / fan-in

```mermaid
flowchart TB
    START(["START"]) --> N1["architecture<br/>4-layer boundary check"]
    START --> N2["database_gate<br/>reason + audit_event pattern"]
    START --> N3["citation_guard<br/>AI output grounding"]
    START --> N4["no_llm_where_unjustified<br/>deliberately-deterministic areas"]
    START --> N5["async_and_config<br/>.Result/.Wait(), CancellationToken, silent config"]
    START --> N6["coding_standards<br/>naming/comment conventions"]
    START --> N7["scoring_invariants<br/>residual risk never zero<br/>(runs only when relevant files change)"]
    START --> N8["audit_trail_integrity<br/>audit_event stays append-only<br/>(runs only when relevant files change)"]
    START --> N9["external_integration_resilience<br/>Mock Systems failure never fails intake or a vote<br/>(runs only when relevant files change)"]

    N1 --> COMPILE["compile_report<br/>merges all 9 findings<br/>into one markdown report"]
    N2 --> COMPILE
    N3 --> COMPILE
    N4 --> COMPILE
    N5 --> COMPILE
    N6 --> COMPILE
    N7 --> COMPILE
    N8 --> COMPILE
    N9 --> COMPILE

    COMPILE --> END(["END"])
```

- **Fan-out:** all nine check nodes run from `START` independently — each gets the same `diff` and `rules` state, but a different single-concern instruction.
- **Fan-in:** `compile_report` is the only node every check feeds into; it waits for all nine before producing the final report.
- **State merge rule:** each check node only writes to its *own* key in a shared `findings` dictionary (`Annotated[dict[str, str], _merge_findings]`). This is required because LangGraph runs fanned-out nodes concurrently — if two nodes tried to write the same state key, it would raise a conflicting-update error. Each node's return value is scoped to just `{"findings": {<its own name>: <its own result>}}`.

---

## 5. What each node actually checks

- **`architecture`**
  - Confirms the 4-layer boundary is respected: `1-API → 2-Infrastructure → 3-Service → 4-Persistence`.
  - Flags business logic placed in a controller, or persistence logic placed in a controller/service.
  - Flags an interface implemented outside `3-Service`/`4-Persistence`.
- **`database_gate`**
  - Confirms any new override of an AI-generated or calculated value takes a mandatory `reason` parameter.
  - Confirms the underlying stored function (`func_...`) writes an `audit_event` row in the same transaction.
  - Flags a schema change made by hand-editing a generated deploy script instead of the SQL project's source function/table definitions.
- **`citation_guard`**
  - Confirms any AI client output (C# `IChatCompletionClient` calls, or Python `get_chat_model()` calls) still drops or flags anything not traceable to its supplied input.
  - Flags a `SystemPrompt` constant that changed without its mirrored `ai/prompts/*.md` file changing (or vice versa).
- **`no_llm_where_unjustified`**
  - Flags a new LLM call added inside an area that is deliberately deterministic today (Policy Research / `func_searchPolicyChunks`, Scoring / `ScoringService`).
  - Reported as "worth a second look," not an automatic failure — this project treats "when NOT to use an LLM" as a deliberate design decision, not an oversight to always reverse.
- **`async_and_config`**
  - Flags `.Result` or `.Wait()` usage.
  - Flags a new async service/persistence call that doesn't forward a `CancellationToken`.
  - Flags new AI-adjacent or external-integration config that silently defaults instead of failing loudly when missing.
- **`coding_standards`**
  - Compares the diff against naming, comment, and layer conventions summarized in `dev_harness/coding-standards.md`.
  - Scoped to flag only clear, concrete violations — not general style nitpicks the rules don't mention.
- **`scoring_invariants`** *(runs only when a changed path contains `scor`, `mitigat`, `residual` or `/configuration/`)*
  - Flags a change that would let residual risk reach zero: a weakened mitigation cap (the factor must stay below 1.0), a dropped `residual_rating > 0` rule, in either the calculation or the config-save path.
  - Flags a score override that no longer needs a reason, a role check or a not-yet-finalized state.
  - Flags a non-deterministic calculation or a silent default for a missing config value.
- **`audit_trail_integrity`** *(runs only when a changed path contains `DB/schema|functions|migrations/` or `audit`)*
  - Flags any UPDATE, DELETE or TRUNCATE of `audit_event`, or anything that disables its guard trigger.
  - Flags an AI-generated or human-editable write that has no audit row in the same call.
  - Flags an audit actor taken from the request body instead of the signed-in user, a wrong `actor_label`, and raw payloads or PII in audit values.
  - Leaves "an override needs a reason" to `database_gate`.
- **`external_integration_resilience`** *(runs only when a changed path contains `DataIngestion`, `MockSystems`, `MockExternalSystems`, `HttpClient`, `Committee` or `Program.cs`)*
  - Flags a failure path that can fail intake or a committee vote. It notes that catching only `HttpRequestException` misses timeouts (`TaskCanceledException`) and bad JSON (`JsonException`).
  - Flags an outbound call with no timeout or cancellation token, and external data used without validation.
  - Flags downstream code reading live external data instead of the immutable snapshot stored at intake, and a new inbound endpoint for an external caller that is unauthenticated or too broad.

**Path gating.** The last three checks carry a one-line `<!-- applies-to: regex -->` directive at the top of their prompt file. The harness matches it against the changed file paths in the diff; if nothing matches, the check reports "OK - not applicable ... (no model call made)" and costs nothing. A check without the directive runs on every diff. The generic web-security checklist (secrets, injection, auth, TLS, error exposure, dependencies) is deliberately not a harness check: the Copilot PR reviewer covers it.

---

## 6. Module layout

```mermaid
flowchart TB
    subgraph harness["harness/ (repo root)"]
        README["README.md<br/>index + scope note"]
        STANDARDS["coding-standards.md<br/>C# / React / Python conventions"]
        RULES["review-rules.md<br/>the checklist itself<br/>(single source of truth)"]
        AIPOLICY["ai-assisted-development.md<br/>human-in-the-loop policy"]
        PROMPT["prompts/code-review.prompt.md<br/>manual/conversational checklist"]

        subgraph dh["dev_harness/ (the tool)"]
            INIT["__init__.py<br/>module docstring + usage"]
            MAIN["__main__.py<br/>CLI entrypoint (argparse)"]
            DIFFSRC["diff_source.py<br/>wraps git diff"]
            RULESPY["rules.py<br/>loads review-rules.md<br/>+ the node prompts<br/>+ their applies-to scopes"]
            NODEPROMPTS["prompts/system.prompt.md<br/>prompts/checks/*.prompt.md<br/>(one file per graph node)"]
            GRAPH["graph.py<br/>the LangGraph itself"]
        end
    end

    RULES -.->|"loaded at runtime"| RULESPY
    NODEPROMPTS -.->|"loaded at runtime"| RULESPY
    MAIN --> DIFFSRC
    MAIN --> GRAPH
    RULESPY --> GRAPH
```

- **`review-rules.md` is the single source of truth.** `rules.py` loads this file's raw text directly — there is no separate copy of the rules baked into the Python code, so the checklist can't drift out of sync between what a human reads and what the harness checks against.
- **The prompts each node runs are files, not Python strings.** `prompts/system.prompt.md` is shared by every node; `prompts/checks/<node>.prompt.md` is the one concern a node owns, and the file name is the node name. `rules.py` loads them, so adding or tuning a check is a prompt-file edit with no change to `graph.py`.
- **`__main__.py` is the only entrypoint.** It wires `diff_source.get_diff()` and `graph.run_harness_with_status()` together and handles CLI flags (`--since`, `--out`, `--max-diff-bytes`). It exits 2 when a check failed to run (see section 9).
- **`graph.py` owns all LangGraph-specific code.** Nothing else in the module imports `langgraph` directly.

---

## 7. How it connects to `ai/langgraph/` (without depending on it)

```mermaid
flowchart LR
    subgraph product["ai/langgraph/ (product service)"]
        LLM["app/llm.py<br/>get_chat_model()"]
        ENV["app/.env<br/>ANTHROPIC_API_KEY, etc."]
    end

    subgraph tool["harness/dev_harness/ (dev tool)"]
        GRAPHPY["graph.py"]
    end

    GRAPHPY -->|"sys.path insert + import"| LLM
    GRAPHPY -->|"load_dotenv(path)"| ENV
```

- `graph.py` adds `ai/langgraph/` to `sys.path` at import time and imports `app.llm.get_chat_model()` directly — no package installation step, no duplicated provider-selection logic.
- It also calls `load_dotenv()` pointed at `ai/langgraph/.env`, so it picks up the same `LLM_PROVIDER`/`ANTHROPIC_API_KEY` configuration already set up for the product service.
- **This is a one-way, convenience-only dependency.** The product service (`ai/langgraph/app/`) has no awareness of, and no dependency on, `harness/dev_harness/`. Deleting the `harness/` folder entirely would not affect the product service.

---

## 8. Running it

```powershell
cd harness
$env:SSL_CERT_FILE="$env:USERPROFILE\.azure\corp_cacert.pem"   # only behind TLS inspection
..\ai\langgraph\.venv\Scripts\python.exe -m dev_harness check
```

- **Review a specific range** instead of the working tree: `... check --since HEAD~1`
- **Save the report to a file**: `... check --out last-report.md`
- **Reading the output:** each section heading matches a node name above; `OK - no issues found` means that concern had nothing to flag, and `OK - not applicable` means a path-gated check skipped itself. Findings include severity, file, line (if known), rule violated, and a recommendation.
- **A check that could not run** (API error, timeout, bad key) shows `CHECK FAILED TO RUN: <error>` in its section, the report opens with "N of M checks failed to run ... incomplete", and the command exits with code 2. Findings never change the exit code.

---

## 9. In CI (Azure DevOps)

- **Pipeline:** `gh-dev-harness` (`.azure-pipelines/harness/dev-harness.yml`). It runs on PRs to `release/1.00` (not for `docs/*`-only changes) and can be run manually. A manual run reviews the changes since a `since` ref, default `HEAD^1`; a PR run always reviews the PR's own diff.
- **Model:** the same `get_chat_model()` as locally, configured from the `ai-review-secrets` variable group (`ANTHROPIC_API_KEY`, `ANTHROPIC_MODEL`, `ANTHROPIC_WORKSPACE_ID`). With no key the step skips and only warns.
- **Report on the PR:** `scripts/dev-harness/post.sh` posts the report as one PR comment (marked `<!-- dev-harness-report -->`) and edits that same comment on every new push, so the PR never fills up with copies. A failed post only warns. It runs as its own step, so the model step never sees the GitHub token.
- **Report as an artifact:** the report is also published as a build artifact, including when a check failed.
- **When it goes red:** if any check failed to run, the review step logs an error and fails, so `gh-dev-harness` shows red on the PR. Findings alone never fail it.
- **Not a required check:** it can never block a merge on its own judgement. It is advice for the human reviewer.

---

## 10. Current limitations (fast-follow candidates)

- Only the diff text is reviewed — the harness doesn't check whether a file *mentioned* as needing an update (e.g. a mirrored prompt doc) was actually changed elsewhere in the repo.
- Only the three domain checks are path-gated; the original six run on every diff.
- The three domain checks were verified for loading and path gating, but their prompts have not yet been tuned against real model output. Treat early findings as a first read, and expect to adjust the prompt files.
- The harness has no model-free fallback: if the key is invalid or expires (the current Anthropic key expires Nov 27, 2026), the checks fail to run rather than silently pass.
- "Gate table sync" (a new epic/AI touchpoint added without a matching row in `docs/governance/human-in-the-loop-gates.md`) and eval-dataset coverage are currently folded loosely into the `database_gate`/`citation_guard` nodes rather than being their own dedicated checks.
