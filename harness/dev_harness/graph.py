"""The dev-harness LangGraph: classify the diff, run only the checks that apply, compile a report.

Mirrors app/graphs/category_mapping.py's shape in ai/langgraph: a _State TypedDict, node
functions, a compiled StateGraph, and a single run_* entrypoint. Reuses ai/langgraph's
get_chat_model() so this harness has no separate provider/config story to maintain.
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Annotated, TypedDict

from langgraph.graph import END, START, StateGraph

# ai/langgraph is a sibling package - add it to sys.path so `from app.llm import get_chat_model`
# works without installing this harness as a dependency of the product service.
_LANGGRAPH_APP_ROOT = Path(__file__).resolve().parents[2] / "ai" / "langgraph"
if str(_LANGGRAPH_APP_ROOT) not in sys.path:
    sys.path.insert(0, str(_LANGGRAPH_APP_ROOT))

from dotenv import load_dotenv  # noqa: E402

from app.llm import get_chat_model  # noqa: E402

load_dotenv(_LANGGRAPH_APP_ROOT / ".env")

from .rules import load_check_prompts, load_review_rules, load_system_prompt  # noqa: E402

# One check per file in dev_harness/prompts/checks/ (the file name is the node name). Each is a
# narrow, single-concern prompt run against the raw diff only - not the whole repo - same
# grounding discipline as the product AI clients. The shared system prompt is
# prompts/system.prompt.md; edit those files, not this module, to change what a check asks.
_CHECKS: dict[str, str] = load_check_prompts()


def _merge_findings(left: dict[str, str], right: dict[str, str]) -> dict[str, str]:
    merged = dict(left)
    merged.update(right)
    return merged


class _State(TypedDict):
    diff: str
    rules: str
    findings: Annotated[dict[str, str], _merge_findings]
    report: str


def _run_check(check_name: str, instruction: str, state: _State) -> str:
    if not state["diff"].strip():
        return "No diff to review."

    model = get_chat_model()
    system_prompt = load_system_prompt()
    user_prompt = (
        f"Your assigned concern:\n{instruction}\n\n"
        f"Project review rules (for grounding only - only report on your assigned concern):\n"
        f"{state['rules']}\n\n"
        f"Diff to review:\n```diff\n{state['diff']}\n```"
    )
    response = model.invoke(
        [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ]
    )
    content = response.content
    if isinstance(content, list):
        content = "".join(b.get("text", "") if isinstance(b, dict) else str(b) for b in content)
    return content.strip()


def _make_check_node(name: str, instruction: str):
    def _node(state: _State) -> dict:
        # Return only this node's delta (not the whole state) - fan-out nodes running
        # concurrently must each write a disjoint key, or LangGraph treats it as a conflicting
        # concurrent update to the same channel.
        return {"findings": {name: _run_check(name, instruction, state)}}

    return _node


def _compile_report(state: _State) -> dict:
    lines = ["# Dev Harness Report", ""]
    any_issue = False
    for name, result in state["findings"].items():
        lines.append(f"## {name.replace('_', ' ').title()}")
        lines.append(result)
        lines.append("")
        if not result.strip().startswith("OK"):
            any_issue = True
    if not any_issue:
        lines.insert(1, "_All checks passed - no violations found._\n")
    return {"report": "\n".join(lines)}


def _build_graph():
    graph = StateGraph(_State)
    graph.add_node("compile_report", _compile_report)
    for name, instruction in _CHECKS.items():
        graph.add_node(name, _make_check_node(name, instruction))
        graph.add_edge(START, name)  # each check node fans out independently from the start
        graph.add_edge(name, "compile_report")
    graph.add_edge("compile_report", END)
    return graph.compile()


def run_harness(diff: str) -> str:
    state: _State = {
        "diff": diff,
        "rules": load_review_rules(),
        "findings": {},
        "report": "",
    }
    compiled = _build_graph()
    result = compiled.invoke(state)
    return result["report"]
