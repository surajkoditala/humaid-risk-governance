# Dev Harness — Technical Deep Dive (LangGraph Implementation)

**Location of the tool itself:** `harness/dev_harness/`
**Status:** Working locally; informational CI pipeline in `.azure-pipelines/harness/dev-harness.yml` (runs on PRs and manually, posts its report on the PR)

**Related:** [`harness/README.md`](../../harness/README.md) · [`dev-harness.md`](dev-harness.md) (the
high-level/non-technical explainer this document expands on) · [`ba-harness.md`](ba-harness.md)
(sibling harness, same documentation format) · [`langgraph-integration.md`](langgraph-integration.md)
(the *product* LangGraph service — unrelated at runtime)

---

## 1. What this document covers

The companion document [`dev-harness.md`](dev-harness.md) explains *what* the dev harness is and
*why* it exists, in plain language. This document is the technical counterpart: it walks through
**every core LangGraph primitive** and shows exactly where it appears (or deliberately does not
appear) in `harness/dev_harness/graph.py`. If you're about to modify the graph, add a check, or
wire in a new LangGraph feature, this is the reference to read first.

LangGraph graphs are built from a small, fixed set of building blocks. This document covers each
one in turn:

| Primitive | Used here? |
|---|---|
| State (`TypedDict` / schema) | Yes |
| Reducers (`Annotated[...]`) | Yes — required for concurrent fan-out writes |
| Nodes | Yes — nine check nodes + one compile node |
| Normal edges | Yes — every edge in this graph |
| Conditional edges | No — candidate fast-follow |
| `StateGraph` / `START` / `END` | Yes |
| `.compile()` / `.invoke()` | Yes |
| Tools / `ToolNode` | No |
| Checkpointers / persistence | No |
| Subgraphs | No |
| Streaming (`.stream()`) | No — `.invoke()` only |

---

## 2. The idea in one sentence

A single `StateGraph` fans a `git diff` out to nine independent, single-concern review nodes that
each call the same chat model with a narrow instruction, then fans back in to one node that
merges their findings into a single markdown report. Three of the nine only call the model when
the diff touches files in their area (section 5).

```mermaid
flowchart TB
    DIFF["Initial state:<br/>{diff, rules, findings: {}}"] --> GRAPH["StateGraph.invoke(state)"]
    GRAPH --> REPORT["Final state:<br/>{..., report: markdown text}"]
```

---

## 3. State — the schema every node reads and writes

LangGraph requires a schema describing the shape of data flowing through the graph. Here it's a
plain `TypedDict`:

```python
class _State(TypedDict):
    diff: str
    rules: str
    findings: Annotated[dict[str, str], _merge_findings]
    report: str
```

- `diff` and `rules` are set once, before the graph runs, and never modified by any node — they're
  effectively read-only inputs threaded through every node's call.
- `findings` is the one field multiple nodes write to **concurrently** (see section 5 — this is
  why it needs a reducer).
- `report` is written exactly once, by the final `compile_report` node.

```mermaid
flowchart LR
    subgraph state["_State (TypedDict)"]
        D["diff: str<br/>(read-only input)"]
        R["rules: str<br/>(read-only input)"]
        F["findings: dict[str, str]<br/>(written concurrently by 9 nodes)"]
        REP["report: str<br/>(written once, at the end)"]
    end
```

---

## 4. Reducers — why `findings` needs `Annotated[..., _merge_findings]`

By default, if two nodes running in the same "superstep" both try to write to the same state key,
LangGraph raises a conflicting-update error — it has no way to know whether the second write
should overwrite the first, or be combined with it. A **reducer** tells LangGraph how to combine
multiple writes to the same key instead of rejecting them.

```python
def _merge_findings(left: dict[str, str], right: dict[str, str]) -> dict[str, str]:
    merged = dict(left)
    merged.update(right)
    return merged
```

`findings` is declared as `Annotated[dict[str, str], _merge_findings]`, so when all nine check
nodes fan out from `START` and run in the same step, each returning `{"findings": {<own key>:
<own result>}}`, LangGraph calls `_merge_findings` repeatedly to fold all nine partial dicts into
one combined `findings` dict — instead of the last writer silently clobbering the other eight.

```mermaid
flowchart TB
    N1["architecture node returns:<br/>{findings: {architecture: ...}}"] --> MERGE
    N2["database_gate node returns:<br/>{findings: {database_gate: ...}}"] --> MERGE
    N3["...7 more nodes..."] --> MERGE
    MERGE["_merge_findings called<br/>once per incoming write,<br/>folding into one dict"] --> RESULT["findings = {<br/>  architecture: ...,<br/>  database_gate: ...,<br/>  ...9 keys total<br/>}"]
```

This is the single most important LangGraph detail in this graph — without the reducer, the
fan-out pattern in section 6 would not be possible at all.

---

## 5. Nodes — plain functions with one job each

A LangGraph node is just a callable: `(state) -> partial_state_update`. Every node here follows
the same shape, built by a shared factory:

```python
_FAILED_PREFIX = "CHECK FAILED TO RUN:"

def _make_check_node(name: str, instruction: str):
    def _node(state: _State) -> dict:
        try:
            result = _run_check(name, instruction, state)
        except Exception as exc:  # any failure of this check must not stop the others
            result = f"{_FAILED_PREFIX} {type(exc).__name__}: {str(exc)[:300]}"
        return {"findings": {name: result}}
    return _node
```

- **Input:** the current `_State` (specifically `state["diff"]` and `state["rules"]`).
- **Work:** `_run_check()` pairs the shared system prompt (`prompts/system.prompt.md`) with the
  one concern this node owns (e.g. `architecture`, `citation_guard` - its instruction text comes
  from `prompts/checks/<node>.prompt.md`), calls `get_chat_model().invoke([...])`, and returns
  the model's text response. Before calling the model it applies the path gate described below.
- **Output:** a *partial* state update — `{"findings": {name: result}}` — never the full state.
  Returning only the delta is what lets nine of these run side by side safely (combined with the
  reducer in section 4).
- **Failure handling:** if a check raises (API error, timeout, bad key), the node records
  `CHECK FAILED TO RUN: <ExcType>: <message>` as its result instead of letting the exception abort
  the run, so the other checks still report. `run_harness_with_status()` returns the list of
  failed checks, `__main__.py` exits with code 2 when it is not empty, and the report opens with
  "N of M checks failed to run ... incomplete". Findings never change the exit code.

There are ten node functions total: nine built by `_make_check_node()` (one per file in
`prompts/checks/`, loaded into the `_CHECKS` dict — `architecture`, `database_gate`,
`citation_guard`, `no_llm_where_unjustified`, `async_and_config`, `coding_standards`,
`scoring_invariants`, `audit_trail_integrity`, `external_integration_resilience`), plus
`_compile_report`, which is hand-written because its job (merge + format) is different in kind
from the other nine (review + report one concern).

### Path gating (inside the node, not a conditional edge)

The last three checks are domain checks that only matter when the diff touches their area. A
prompt file may start with a directive:

```
<!-- applies-to: (?i)(scor|mitigat|residual|/configuration/) -->
```

`rules.py` strips the directive from the prompt text (`load_check_prompts()`) and compiles the
regex separately (`load_check_scopes()`). `_run_check()` then reads the changed paths from the
`diff --git a/X b/Y` lines (`_changed_files()`); if the check declares a scope and no changed path
matches (`re.search`), it returns "OK - not applicable ... (no model call made)" without calling
the model. A check with no directive always runs.

| Check | `applies-to` matches paths containing |
|---|---|
| `scoring_invariants` | `scor`, `mitigat`, `residual`, `/configuration/` |
| `audit_trail_integrity` | `DB/(schema\|functions\|migrations)/`, `audit` |
| `external_integration_resilience` | `DataIngestion`, `MockSystems`, `MockExternalSystems`, `HttpClient`, `Committee`, `Program.cs` |

All nine nodes are still scheduled from `START` on every run; the gate decides inside the node
whether it spends a model call. That keeps the graph's edges static (section 6).

```mermaid
flowchart LR
    STATE["state: _State"] --> NODE["_node(state)"]
    NODE --> CHECK["_run_check(name, instruction, state)"]
    CHECK --> MODEL["get_chat_model().invoke(\n  [system_prompt, user_prompt]\n)"]
    MODEL --> RETURN["return {'findings': {name: result}}"]
```

`_compile_report` is the one node that reads the *entire* `findings` dict (not just its own slice)
and writes `report` — it's a fan-in aggregation node, not a review node:

```python
def _compile_report(state: _State) -> dict:
    lines = ["# Dev Harness Report", ""]
    failed = _failed_checks(state["findings"])   # results starting with _FAILED_PREFIX
    if failed:
        lines.insert(1, f"**{len(failed)} of {len(state['findings'])} checks failed to run: ...**")
    any_issue = False
    for name, result in state["findings"].items():
        lines.append(f"## {name.replace('_', ' ').title()}")
        lines.append(result)
        if not result.strip().startswith("OK"):
            any_issue = True
    ...
    return {"report": "\n".join(lines)}
```

---

## 6. Edges — normal edges only, fan-out then fan-in

LangGraph supports two kinds of edges: **normal edges** (always-taken, fixed pathways) and
**conditional edges** (a routing function picks the next node at runtime based on state). This
graph uses only normal edges — there is no branching logic anywhere in it today:

```python
def _build_graph():
    graph = StateGraph(_State)
    graph.add_node("compile_report", _compile_report)
    for name, instruction in _CHECKS.items():
        graph.add_node(name, _make_check_node(name, instruction))
        graph.add_edge(START, name)              # fan-out: every check starts in parallel
        graph.add_edge(name, "compile_report")    # fan-in: every check feeds the same node
    graph.add_edge("compile_report", END)
    return graph.compile()
```

```mermaid
flowchart TB
    START(["START"]) --> N1["architecture"]
    START --> N2["database_gate"]
    START --> N3["citation_guard"]
    START --> N4["no_llm_where_unjustified"]
    START --> N5["async_and_config"]
    START --> N6["coding_standards"]
    START --> N7["scoring_invariants<br/>(path-gated)"]
    START --> N8["audit_trail_integrity<br/>(path-gated)"]
    START --> N9["external_integration_resilience<br/>(path-gated)"]
    N1 --> COMPILE["compile_report"]
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

- **Fan-out:** nine `add_edge(START, name)` calls mean all nine check nodes are scheduled in the
  same superstep, with no ordering guarantee or dependency between them.
- **Fan-in:** nine `add_edge(name, "compile_report")` calls mean `compile_report` only runs once
  *all* nine predecessors have completed and written their piece of `findings` — LangGraph waits
  for every incoming edge before running a node, so this is a true join, not a race.
- **No conditional edges today.** A conditional edge would look like
  `graph.add_conditional_edges(START, route_fn, {"yes": "database_gate", "no": "compile_report"})`.
  The path-gated checks achieve the same saving without one: the node itself returns "not
  applicable" when no changed file matches (section 5), so the edges stay static. Moving that
  decision into a routing function would only change where the check runs, not what it costs.

---

## 7. `StateGraph`, `.compile()`, and `.invoke()` — assembly and execution

`StateGraph(_State)` is the builder; `add_node`/`add_edge` populate it; `.compile()` turns the
builder into an immutable, runnable graph (a `CompiledGraph`); `.invoke(state)` runs it once,
synchronously, start to finish, and returns the final state:

```python
def run_harness_with_status(diff: str) -> tuple[str, list[str]]:
    state: _State = {"diff": diff, "rules": load_review_rules(), "findings": {}, "report": ""}
    compiled = _build_graph()          # StateGraph(...).compile()
    result = compiled.invoke(state)    # runs START -> fan-out -> fan-in -> END, synchronously
    return result["report"], _failed_checks(result["findings"])
```

`run_harness(diff)` is a thin wrapper that returns only the report; the CLI uses
`run_harness_with_status()` so it can exit 2 when a check failed to run.

- The graph is rebuilt and recompiled on **every CLI invocation** (`_build_graph()` is called
  fresh inside `run_harness_with_status()`) — there's no module-level singleton graph. This is cheap enough
  for a one-shot CLI tool and avoids any shared mutable graph state across runs.
- `.invoke()` is used, not `.stream()`. The harness waits for the entire run to finish and returns
  one final report string — there's no need to stream intermediate node output to the terminal
  incrementally, since all the checks need to finish before the report is meaningful anyway.

---

## 8. What's deliberately NOT used, and why

LangGraph supports several more advanced primitives that this harness intentionally does not use:

- **Tools / `ToolNode` / tool-calling** — every node reasons directly over text already present in
  `state` (the diff and the rules). No node needs to call an external API, query a database, or
  invoke a function the model chooses at runtime, so there's nothing to bind as a tool. (Contrast
  with `ai/langgraph/app/graphs/`, the product graphs, where tool-style integrations are relevant.)
- **Checkpointers (`MemorySaver`, etc.) / persistence** — `run_harness()` compiles and invokes the
  graph fresh on every CLI call with an empty `findings` dict; there is no multi-turn memory, no
  resuming a paused run, and no need to persist state between invocations. This would become
  relevant if the harness ever needed to remember prior findings across commits or pause
  mid-graph for a human approval step.
- **Conditional edges** — see section 6; every check node is always scheduled. The three
  path-gated checks skip their model call from inside the node when the diff touches nothing in
  their area.
- **Subgraphs** — the graph is flat; none of the nine check nodes is itself a compiled graph.
- **Human-in-the-loop interrupts (`interrupt()`)** — the harness is already a reporting-only tool
  that never auto-applies anything, so there's no in-graph decision point that needs a pause; the
  human-in-the-loop step happens entirely *after* the graph finishes, when a person reads the
  report.

---

## 9. End-to-end execution trace

```mermaid
flowchart TB
    A["__main__.py: check command"] --> B["diff_source.get_diff()<br/>(git diff HEAD or --since ref)"]
    B --> C["rules.load_review_rules()<br/>(reads review-rules.md text)"]
    C --> D["run_harness_with_status(diff)"]
    D --> E["_build_graph():<br/>StateGraph(_State) -> compile()"]
    E --> F["compiled.invoke({diff, rules,<br/>findings: {}, report: ''})"]
    F --> G["START fans out to<br/>9 check nodes (section 6)"]
    G --> H["each node: _run_check() -><br/>path gate, then<br/>get_chat_model().invoke(...)<br/>(section 5)"]
    H --> I["findings merged via<br/>_merge_findings reducer<br/>(section 4)"]
    I --> J["compile_report fan-in node<br/>formats markdown (section 5)"]
    J --> K["END — result['report']<br/>returned to __main__.py"]
    K --> L["printed to terminal,<br/>optionally written to --out file"]
    L --> M["exit 0, or exit 2 if any check<br/>failed to run (findings never<br/>change the exit code)"]
```

---

## 10. Current limitations, in LangGraph-specific terms

- **Path gating is partial.** Only the three domain checks declare an `applies-to` scope. The
  original six still call the model on every diff, even when clearly irrelevant (e.g.
  `database_gate` on a diff that touches no persistence code). Adding an `applies-to` line to
  their prompt files is the natural next step, and needs no code change (see section 5).
- **The scopes are path regexes, not understanding.** A check is skipped only when no changed
  file *path* matches, so a relevant change in an oddly named file will not trigger it.
- **No checkpointing.** Each run is fully isolated; there is no way to resume, compare against a
  prior run's findings, or accumulate history across multiple `check` invocations without adding
  a checkpointer and a thread/session id.
- **No tool use.** If a future check needed to look something up (e.g. query the actual DB schema
  instead of inferring it from the diff), that would require introducing a `ToolNode` and binding
  tools to the model — a meaningfully different shape than the current pure-text-reasoning nodes.
