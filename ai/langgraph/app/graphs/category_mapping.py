"""Category Mapping graph - proposes which named framework categories (from a fixed,
supplied allowed list) apply to a change request's title/description.

Mirrors src/3-Service/Humaid.RiskGovernance.AdminUI.AI/CategoryMappingAiClient.cs's contract,
including its citation-fabrication guard: any category ID the model returns that isn't in
allowed_categories is dropped, never passed through (see ai/README.md).

Uses whichever chat model app.llm.get_chat_model() resolves to (LLM_PROVIDER env var -
gemini by default, see .env.example). This is a minimal single-node graph - a real multi-step
LangGraph (e.g. propose -> self-critique -> filter-against-allow-list as separate nodes) can
replace the body of `_propose` without changing run_category_mapping's signature.
"""

from __future__ import annotations

import json

from langgraph.graph import StateGraph, END
from typing_extensions import TypedDict

from app.llm import get_chat_model
from app.schemas import CategoryMappingRequest, CategoryMappingResponse, ProposedCategory


class _State(TypedDict):
    request: CategoryMappingRequest
    proposed: list[ProposedCategory]


_SYSTEM_PROMPT = (
    "You map a bank change request's title/description onto a fixed set of named risk "
    "categories. You may ONLY propose category IDs from the allowed list you are given - "
    "never invent a new one. Respond with strict JSON: "
    '{"proposals": [{"category_id": "...", "rationale": "..."}]}'
)


def _propose(state: _State) -> _State:
    request = state["request"]
    allowed_ids = {c.id for c in request.allowed_categories}

    model = get_chat_model()
    allowed_list_text = "\n".join(f"- {c.id}: {c.name}" for c in request.allowed_categories)
    user_prompt = (
        f"Change request title: {request.change_request_title}\n"
        f"Change request description: {request.change_request_description}\n\n"
        f"Allowed categories:\n{allowed_list_text}"
    )

    response = model.invoke(
        [
            {"role": "system", "content": _SYSTEM_PROMPT},
            {"role": "user", "content": user_prompt},
        ]
    )

    try:
        parsed = json.loads(response.content)
        proposed = [
            ProposedCategory(category_id=p["category_id"], rationale=p.get("rationale", ""))
            for p in parsed.get("proposals", [])
        ]
    except (json.JSONDecodeError, KeyError, TypeError):
        # Model didn't return valid JSON - fail safe to no proposals rather than guessing.
        proposed = []

    # Citation guard: never return a category_id outside the supplied allow-list.
    state["proposed"] = [p for p in proposed if p.category_id in allowed_ids]
    return state


_graph = StateGraph(_State)
_graph.add_node("propose", _propose)
_graph.set_entry_point("propose")
_graph.add_edge("propose", END)
_compiled = _graph.compile()


def run_category_mapping(request: CategoryMappingRequest) -> CategoryMappingResponse:
    result = _compiled.invoke({"request": request, "proposed": []})
    return CategoryMappingResponse(proposed_categories=result["proposed"])
