"""The ba-harness LangGraph: review a drafted or existing epic/story against
ba_harness/writing-standards.md, and (for drafts) propose structured Boards fields.

Mirrors dev_harness/graph.py's shape - a _State TypedDict, node functions, a compiled
StateGraph - and reuses ai/langgraph's get_chat_model() the same way, so there's no separate
provider/config story for this harness either.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import TypedDict

from langgraph.graph import END, START, StateGraph

_LANGGRAPH_APP_ROOT = Path(__file__).resolve().parents[2] / "ai" / "langgraph"
if str(_LANGGRAPH_APP_ROOT) not in sys.path:
    sys.path.insert(0, str(_LANGGRAPH_APP_ROOT))

from dotenv import load_dotenv  # noqa: E402

from app.llm import get_chat_model  # noqa: E402

load_dotenv(_LANGGRAPH_APP_ROOT / ".env")

from .standards import load_writing_standards  # noqa: E402

_REVIEW_SYSTEM_PROMPT = (
    "You are a business analyst reviewer for this project's epics and stories. You are given "
    "the project's writing standards and a single epic or story (either already in Azure "
    "Boards, or a rough draft not yet created). Check it against the standards only - do not "
    "invent additional rules.\n\n"
    "Respond with exactly this structure:\n"
    "Verdict: <Pass|Needs changes>\n"
    "Findings:\n"
    "- <one bullet per issue, or 'None' if Pass>\n"
)

_SENSITIVE_DATA_SYSTEM_PROMPT = (
    "You are a data-sensitivity reviewer for this project's epics and stories. Your ONLY job is "
    "to check whether the item involves sending real vendor, bank, or product data to an AI/LLM "
    "call without an explicit mock/synthetic-data substitution. Do not comment on anything else "
    "(formatting, acceptance criteria style, tagging, etc.) - another reviewer covers that.\n\n"
    "Flag the item if:\n"
    "- It describes an AI/LLM call that would plausibly receive real vendor, bank account/"
    "routing, or product/policy data, AND\n"
    "- The story does not explicitly state that only mock/synthetic data is used for that call, "
    "or does not explain why the data involved is not actually sensitive.\n\n"
    "Respond with exactly this structure:\n"
    "Verdict: <Pass|Needs changes>\n"
    "Findings:\n"
    "- <one bullet per issue, or 'None' if Pass>\n"
)

_EXTRACT_SYSTEM_PROMPT = (
    "You convert a rough, free-text epic or story description into the structured fields this "
    "project's Azure Boards items require. Follow the writing standards given to you exactly - "
    "title format, Given/When/Then acceptance criteria, the [AI] tagging rule, and tag format.\n\n"
    "Respond with ONLY a JSON object (no markdown fences, no commentary) with these exact keys:\n"
    '{\n'
    '  "work_item_type": "Epic" or "Story",\n'
    '  "title": "...",\n'
    '  "description_html": "<p>As a ..., I want ..., so that ....</p>" (Story only, else ""),\n'
    '  "acceptance_criteria_html": "<ul><li>Given ... when ... then ...</li>...</ul>" (Story only, else ""),\n'
    '  "tags": "category tag; epic tag" (Story) or "category tag" (Epic),\n'
    '  "is_ai_touchpoint": true/false,\n'
    '  "needs_human_review_pair": true/false (true only if is_ai_touchpoint is true and no '
    'paired human-review story was mentioned in the draft)\n'
    '}'
)


class _State(TypedDict):
    standards: str
    item_text: str
    mode: str  # "review" or "extract"
    review_result: str
    sensitive_data_result: str
    extracted: dict


def _load_standards_node(state: _State) -> dict:
    return {"standards": load_writing_standards()}


def _review_node(state: _State) -> dict:
    model = get_chat_model()
    user_prompt = (
        f"Writing standards:\n{state['standards']}\n\n"
        f"Epic/story to review:\n{state['item_text']}"
    )
    response = model.invoke(
        [
            {"role": "system", "content": _REVIEW_SYSTEM_PROMPT},
            {"role": "user", "content": user_prompt},
        ]
    )
    content = response.content
    if isinstance(content, list):
        content = "".join(b.get("text", "") if isinstance(b, dict) else str(b) for b in content)
    return {"review_result": content.strip()}


def _sensitive_data_node(state: _State) -> dict:
    model = get_chat_model()
    user_prompt = (
        f"Writing standards (for grounding only - only report on sensitive data/AI usage):\n"
        f"{state['standards']}\n\n"
        f"Epic/story to review:\n{state['item_text']}"
    )
    response = model.invoke(
        [
            {"role": "system", "content": _SENSITIVE_DATA_SYSTEM_PROMPT},
            {"role": "user", "content": user_prompt},
        ]
    )
    content = response.content
    if isinstance(content, list):
        content = "".join(b.get("text", "") if isinstance(b, dict) else str(b) for b in content)
    return {"sensitive_data_result": content.strip()}


def _combine_review_node(state: _State) -> dict:
    combined = (
        f"## Writing Standards Review\n{state['review_result']}\n\n"
        f"## Sensitive Data & AI Usage Review\n{state['sensitive_data_result']}"
    )
    return {"review_result": combined}


def _strip_json_fence(text: str) -> str:
    text = text.strip()
    if text.startswith("```"):
        lines = text.splitlines()
        lines = lines[1:] if lines and lines[0].startswith("```") else lines
        if lines and lines[-1].strip().startswith("```"):
            lines = lines[:-1]
        text = "\n".join(lines)
    return text.strip()


def _extract_node(state: _State) -> dict:
    model = get_chat_model()
    user_prompt = (
        f"Writing standards:\n{state['standards']}\n\n"
        f"Rough draft to convert:\n{state['item_text']}"
    )
    response = model.invoke(
        [
            {"role": "system", "content": _EXTRACT_SYSTEM_PROMPT},
            {"role": "user", "content": user_prompt},
        ]
    )
    content = response.content
    if isinstance(content, list):
        content = "".join(b.get("text", "") if isinstance(b, dict) else str(b) for b in content)
    parsed = json.loads(_strip_json_fence(content))
    return {"extracted": parsed}


def _route(state: _State) -> list[str]:
    return ["review", "sensitive_data"] if state["mode"] == "review" else ["extract"]


def _build_graph():
    graph = StateGraph(_State)
    graph.add_node("load_standards", _load_standards_node)
    graph.add_node("review", _review_node)
    graph.add_node("sensitive_data", _sensitive_data_node)
    graph.add_node("combine_review", _combine_review_node)
    graph.add_node("extract", _extract_node)

    graph.add_edge(START, "load_standards")
    graph.add_conditional_edges(
        "load_standards", _route, {"review": "review", "sensitive_data": "sensitive_data", "extract": "extract"}
    )
    # Review mode fans out to two independent checks (writing standards, sensitive data/AI
    # usage) that both run against the same item_text/standards, then fans back in to
    # combine_review - mirrors dev_harness/graph.py's fan-out/fan-in shape.
    graph.add_edge("review", "combine_review")
    graph.add_edge("sensitive_data", "combine_review")
    graph.add_edge("combine_review", END)
    graph.add_edge("extract", END)
    return graph.compile()


def run_review(item_text: str) -> str:
    """Review an existing or drafted epic/story against the writing standards, including a
    dedicated check for sensitive vendor/bank/product data being sent to AI without mock
    substitution."""
    state: _State = {
        "standards": "",
        "item_text": item_text,
        "mode": "review",
        "review_result": "",
        "sensitive_data_result": "",
        "extracted": {},
    }
    result = _build_graph().invoke(state)
    return result["review_result"]


def run_extract(item_text: str) -> dict:
    """Convert a rough draft into structured Boards fields, ready for boards_client.create_*."""
    state: _State = {
        "standards": "",
        "item_text": item_text,
        "mode": "extract",
        "review_result": "",
        "sensitive_data_result": "",
        "extracted": {},
    }
    result = _build_graph().invoke(state)
    return result["extracted"]
