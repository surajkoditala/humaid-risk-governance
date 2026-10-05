# Evaluation: should the Workbench adopt LangGraph?

**Status:** proposal for team decision — 2026-09-25. Nothing in this note has been decided or built.
**Raised:** in the 22 Sep 2026 standup, when a LangGraph sample was shared as a possible fit for the AI touchpoints. **Deadline context:** submission is 30 Sep 2026, and the judging rubric weights "AI harness and orchestration" at 30% (see `CLAUDE.md`).

---

## Recommendation

**Do not adopt LangGraph for this submission. Keep the current architecture and describe it explicitly as the orchestration harness it already is.** LangGraph is a Python/JavaScript framework for workflows where an LLM decides what runs next; this project is a .NET application with a fixed, deliberately mostly-deterministic sequence, five days from the deadline. Adopting it would add a second runtime and deployment path and would weaken, not strengthen, the "when not to use an LLM" story. If the team wants a graph-orchestration framework in the codebase, the .NET-native option (Microsoft Agent Framework) is a better fit, but it is a post-hackathon refactor.

---

## What LangGraph is

An open-source framework for building AI workflows as a **graph**: *nodes* are steps (an LLM call, a tool, or plain code), *edges* decide what runs next (including conditional branches), and a shared **state object** is passed along, with each node returning only what it adds or changes. It also provides checkpointing (save state after each step and resume after a failure), interrupts (pause for a human to inspect or edit the state), and streaming. It is model-agnostic and does not require LangChain. The documentation covers Python, and a JavaScript/TypeScript version exists; we found no .NET version.

---

## How orchestration works in the Workbench today

Facts below are from `ai/README.md`, `docs/governance/human-in-the-loop-gates.md` and the code.

- **Three AI calls, each narrow.** Category mapping (Epic 2), document extraction (Epic 4) and narrative drafting (Epic 5) — `CategoryMappingAiClient`, `DocumentExtractionAiClient`, `NarrativeDraftingAiClient`. Policy research (Epic 3) and scoring (Epic 7) are deliberately deterministic.
- **One model abstraction.** All three depend on `IChatCompletionClient`; `AI_PROVIDER` selects the implementation (Anthropic or Azure AI Foundry) with no prompt or parsing changes.
- **Grounding on every call.** Each client is given a fixed set of categories, policy excerpts or source text and drops or flags anything it cannot trace back to that input (the citation-fabrication guard).
- **Human gates enforced in code.** Analyst review, reason-required edits, and a finalize step that blocks routing to committee until each narrative section is analyst-reviewed and each mapped category has a recorded policy-reliance decision.
- **Durable, audited state.** Workflow position is a status on the change request plus rows in Postgres; every change is written to an append-only audit trail.
- **Evaluation.** `evals/` scores the three AI clients against fixed datasets.

The sequence itself is fixed: the code, not a model, decides that mapping precedes drafting and that drafting precedes review.

---

## Mapping: LangGraph concepts to what we already have

| LangGraph concept | Workbench equivalent |
|---|---|
| Node | The service or client that performs one step (`CategoryMappingAiClient`, `func_searchPolicyChunks`, `ScoringService`, analyst review) |
| Edge / routing | A fixed sequence enforced by service calls and status checks (for example, a vote is only accepted while the request is `PendingCommittee`); no model chooses the next step |
| State object | Postgres rows keyed by change request ID (mappings, extracted fields, narrative sections, scores, votes) plus the status field |
| Checkpointing | State is durable in the database by design, and every change is audited |
| Interrupt / human-in-the-loop | The analyst-review and committee gates (see `human-in-the-loop-gates.md`) |
| Model abstraction | `IChatCompletionClient` and `AI_PROVIDER` |

The shape is already a graph; what we lack is a framework that draws and executes it.

---

## Fit assessment

**What adoption would give us**
- An explicit, inspectable graph definition and visualization of the workflow.
- Built-in pause/resume for human review instead of our own status checks.
- A recognizable orchestration story for reviewers who look for a named framework.

**Why it does not fit this project now**
- **Stack mismatch.** The backend is C#/.NET. LangGraph means adding a Python service: a new container, a new pipeline and security scan, a new deployment target and new configuration — with about five days left.
- **Different problem.** LangGraph's strength is dynamic, LLM-driven routing and loops. Our design keeps the LLM to three bounded calls inside a fixed process. A supervisor agent choosing the next step would add nondeterminism where we currently have guarantees (for example, residual risk can never reach zero, enforced in the database and in C#).
- **It would dilute a scored strength.** The rubric rewards knowing when *not* to use an LLM (5%), and `ai/README.md` documents exactly that judgement for Epics 3 and 7.
- **Rewrite risk.** Moving state into a framework's state object would duplicate, or replace, the database-backed state that the audit trail and the human gates depend on.

---

## Options

| Option | What it means | Effort | Risk | Assessment |
|---|---|---|---|---|
| **A. Keep and document** | No code change. Describe the existing design as the orchestration harness: the workflow drawn as a graph, the state model, the gates. | Very low | None | **Recommended for this submission** |
| B. Microsoft Agent Framework | Graph workflows in .NET with checkpointing and human-approval pauses; reported stable at version 1.0 in April 2026, and it fits our stack and Azure. | High (refactor) | Medium | Reasonable post-hackathon direction; too large to start now |
| C. Isolated LangGraph demonstrator | A small, clearly-labelled experiment (for example under `ai/`) that is not wired into the app. | Low–medium | Low | Optional; shows awareness, adds no product value |
| D. Adopt LangGraph in the app | Add a Python orchestration service and route the AI touchpoints through it. | High | High | Not recommended |

---

## If we choose option A, the follow-up is small

- Add a short "how the pieces are orchestrated" section to `ai/README.md` that names the nodes (clients and deterministic steps), the routing (status checks), the state (database), and the human gates.
- Point to the existing workflow flowchart in `docs/architecture/ecosystem-diagram.md` (§4) as the graph.
- State plainly in the presentation that a framework was evaluated and deliberately not adopted, and why.

---

## Open questions for the team

1. Is option A enough for the "AI harness and orchestration" criterion, or does the team want visible orchestration code (option C)?
2. If option C, who owns it, and does it stay out of the deployed images?
3. Should option B be recorded as the intended post-hackathon direction?

---

## Sources

- LangGraph overview — <https://docs.langchain.com/oss/python/langgraph/overview>
- Microsoft Agent Framework Version 1.0 — <https://devblogs.microsoft.com/agent-framework/microsoft-agent-framework-version-1-0/>
- Microsoft Agent Framework workflows, human-in-the-loop — <https://learn.microsoft.com/en-us/agent-framework/workflows/human-in-the-loop>
