# Dev Harness

Standards and tooling for **writing and reviewing code** in this repo (one of three sub-harnesses
under `harness/` — see [`../README.md`](../README.md) for the others).

| File | Purpose |
|---|---|
| [`coding-standards.md`](coding-standards.md) | C#, React/TypeScript, and Python conventions for this repo |
| [`review-rules.md`](review-rules.md) | The checklist a human (or the CLI below) reviews every change against |
| [`ai-assisted-development.md`](ai-assisted-development.md) | Human-in-the-loop policy for AI-drafted code in this repo |
| [`prompts/code-review.prompt.md`](prompts/code-review.prompt.md) | Manual/conversational review prompt mirroring `review-rules.md` |
| [`prompts/system.prompt.md`](prompts/system.prompt.md) | System prompt every graph node runs with (output format, "stay in your lane") |
| [`prompts/checks/`](prompts/checks/) | One `<node>.prompt.md` per graph node - the single concern that node reviews. The file name is the node name; add a file to add a check |

A LangGraph CLI that reviews a local git diff against [`review-rules.md`](review-rules.md)
before you commit. It is **dev tooling only** — never called by the deployed Workbench, and
separate from `ai/langgraph/`'s product graphs (Category Mapping, Document Extraction, Narrative
Drafting), even though it reuses the same `get_chat_model()` and local `.env` for convenience.

## What it checks

One LangGraph node per concern, each scoped to a narrow instruction and the raw diff only (never
the whole repo):

| Node | Concern |
|---|---|
| `architecture` | 4-layer boundary violations |
| `database_gate` | `reason` + `audit_event` override pattern; schema changes via the SQL project |
| `citation_guard` | AI client output grounding; prompt file mirroring |
| `no_llm_where_unjustified` | New LLM calls inside deliberately-deterministic areas |
| `async_and_config` | `.Result`/`.Wait()`, `CancellationToken` forwarding, silent config defaults |
| `coding_standards` | Naming/comment conventions from `coding-standards.md` |

Findings are compiled into a single markdown report. Nothing is auto-fixed or auto-committed —
you review the report yourself, consistent with this repo's "system prepares, humans decide" rule
applied to its own development process.

## Running it

Uses the same Python environment as `ai/langgraph/` (it imports `app.llm` from there directly —
no separate install needed):

```powershell
cd ai\langgraph
$env:SSL_CERT_FILE="$env:USERPROFILE\.azure\corp_cacert.pem"   # only behind TLS inspection
cd ..\..\harness
..\ai\langgraph\.venv\Scripts\python.exe -m dev_harness check
```

Or diff against a specific ref:

```powershell
..\ai\langgraph\.venv\Scripts\python.exe -m dev_harness check --since HEAD~1 --out last-report.md
```

## Provider

Uses `ai/langgraph/.env`'s `LLM_PROVIDER` (Anthropic today, via `ANTHROPIC_API_KEY` /
`ANTHROPIC_MODEL` / `ANTHROPIC_WORKSPACE_ID`). Switching that `.env` to `gemini` switches this
tool too — same as it does for the product graphs.

## Known v1 limitations

- Only the diff's text is reviewed — no cross-referencing of whether a mentioned file (e.g. a
  mirrored prompt doc) was actually updated elsewhere in the repo.
- CI integration is a draft, informational pipeline (`.azure-pipelines/harness/dev-harness.yml`)
  that publishes the report as a build artifact; it is not a required check and does not comment
  on the PR yet.
- Eval-dataset coverage checks and "gate table sync" (new epic added without a
  `human-in-the-loop-gates.md` row) are not yet separate nodes — currently folded loosely into
  `database_gate`/`citation_guard`. Fast-follow if this proves too coarse in practice.
