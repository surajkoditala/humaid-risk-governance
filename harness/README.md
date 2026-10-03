# Harness — Rules, Standards, and Dev Tooling

This folder holds everything that governs **how work gets created and reviewed** in this repo,
separate from the product code itself (`src/`, `webapp/`, `ai/`). Nothing here ships with the
application. It's organized as a set of standards-domain sub-harnesses, each self-contained with
its own rules and (where applicable) tooling.

Modeled on the review-standards approach used in `erc-insurity-integration/.github`, adapted to
this repo's actual architecture (stored-function Postgres persistence, not EF Core migrations;
the `reason` + `audit_event` override pattern, not `OperationResult<T>`; the citation-fabrication
guard, not Verisk data guardrails).

## Contents

| Sub-harness | Purpose | Status |
|---|---|---|
| [`dev_harness/`](dev_harness/) | Coding standards + human-in-the-loop policy + LangGraph CLI that reviews a local git diff | Active |
| [`epic_and_story_harness/`](epic_and_story_harness/) | Rules/standards for writing epics, stories, bugs, and issues | Standards only (no tooling yet) |
| [`test_case_harness/`](test_case_harness/) | Rules/standards for writing automated, unit, and manual test cases | Standards only (no tooling yet) |

Each sub-harness folder has its own `README.md` describing what it covers in detail.

See [`docs/architecture/dev-harness.md`](../docs/architecture/dev-harness.md) for the full
architecture writeup of the `dev_harness` CLI, including node-by-node flow diagrams.

## How this differs from the product's own AI harness

`ai/README.md` documents the Workbench's **product** AI harness (Category Mapping, Document
Extraction, Narrative Drafting). This folder is a **development-process** harness: it helps the
team write and review epics/stories, code, and test cases for this repo. These are unrelated at
runtime — nothing under `harness/` is ever called by the deployed application. `dev_harness/`
reuses the same local Anthropic credentials only because it's convenient during local
development, not because the two systems are connected.

See [`docs/architecture/langgraph-evaluation.md`](../docs/architecture/langgraph-evaluation.md)
for why the *product* does not use LangGraph. That recommendation is unaffected by this folder —
`dev_harness/` is dev tooling, not an orchestration framework inside the shipped API.
