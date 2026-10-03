# LangGraph orchestration service

A standalone Python service (FastAPI + LangGraph) that can stand in for the existing C#
AI orchestration (`src/3-Service/Humaid.RiskGovernance.AdminUI.AI`) for the same three
AI touchpoints — Category Mapping, Document Extraction, Narrative Drafting — without the
rest of the Workbench (controllers, services, webapp) knowing or caring which engine
answered. Same relationship as `AI_PROVIDER` (`Anthropic` vs `AzureFoundry`) one level up:
this is an alternate *implementation* behind the same `ICategoryMappingAiClient` /
`IDocumentExtractionAiClient` / `INarrativeDraftingAiClient` interfaces
(`src/2-Infrastructure/.../Interfaces/Ai/`), not a replacement for them.

Why its own service rather than living inside the .NET solution: LangGraph is Python-only,
so it can't be a project in `Humaid.RiskGovernance.AdminUI.slnx`. It's called over HTTP,
the same pattern already used for Anthropic, Azure Foundry, and Mock Systems — one more
named `HttpClient` in `Program.cs`, not a special case.

## How this plugs into the .NET backend

```
AdminUI.Web
  |-- ICategoryMappingAiClient      (interface, unchanged)
	|-- CategoryMappingAiClient          (existing - calls IChatCompletionClient directly)
	|-- LangGraphCategoryMappingAiClient (new - calls this service over HTTP)
```

A new switch (name TBD, e.g. `AI_ORCHESTRATION_PROVIDER` = `DotNet` | `LangGraph`) in
`Program.cs` decides which of the two implementations gets registered for all three
interfaces — mirroring the existing `AI_PROVIDER` switch's "fail loudly if misconfigured,
default to what works today" rule. The C# side isn't wired up yet; this folder is the
Python side only, so you can iterate on the graphs before deciding on the exact wire
format returned to .NET.

## Endpoints (planned)

One route per AI touchpoint, request/response shapes mirroring the existing C# DTOs
(`src/2-Infrastructure/.../Models/...`) so wiring the .NET client is a straight mapping,
not a redesign:

| Route | Mirrors |
|---|---|
| `POST /category-mapping` | `ICategoryMappingAiClient.ProposeAsync` |
| `POST /document-extraction` | `IDocumentExtractionAiClient` |
| `POST /narrative-drafting` | `INarrativeDraftingAiClient` |

Every response must still honor the citation-fabrication guard described in `ai/README.md`
— nothing invented outside the supplied categories/facts/policy excerpts gets returned
un-flagged.

## Model provider

`app/llm.py`'s `get_chat_model()` centralizes provider selection via the `LLM_PROVIDER` env
var - mirrors the .NET side's `AI_PROVIDER` switch in `Program.cs` (one place decides, every
graph just gets a LangChain chat model back):

| `LLM_PROVIDER` | Needs | Notes |
|---|---|---|
| `gemini` (default) | `GOOGLE_API_KEY`, `GEMINI_MODEL` | Google AI Studio key - https://aistudio.google.com/apikey |
| `anthropic` | `ANTHROPIC_API_KEY`, `ANTHROPIC_MODEL` | Same key you'd use for the .NET `ClaudeApiClient` |
| `foundry` | — | Not implemented yet in this service |

Missing config for the selected provider fails loudly at first use, same "flag explicitly,
don't silently guess" rule as the rest of this repo.

## Local dev

```powershell
cd ai/langgraph
python -m venv .venv
.venv\Scripts\activate
pip install -e .
copy .env.example .env      # set LLM_PROVIDER and the matching key (GOOGLE_API_KEY for gemini)
uvicorn app.main:app --reload --port 8100
```

`GET http://localhost:8100/health` should return `{"status": "ok"}`.

## Docker

Not yet added to `ops/docker-compose.app.yml` — add a `langgraph` service there (own
Dockerfile in this folder, port `8100`) once the .NET-side client/switch exists, the same
way `workbench`/`mockapi`/`webapp` are wired today.
