"""Wraps the `az boards` / `az devops` CLI so the harness never needs its own separate Azure
DevOps auth story - it reuses whatever `az devops login` session is already active locally,
exactly as described in CLAUDE.md's "Azure DevOps Boards" section.

Nothing here stores or prompts for a PAT - that stays a manual, out-of-band `az devops login`
step the developer does themselves (and revokes when done), same as today.
"""

from __future__ import annotations

import json
import subprocess

ORGANIZATION = "https://dev.azure.com/Myridius-Insurity"
PROJECT = "humaid-risk-governance"


class BoardsError(RuntimeError):
    """Raised when the az CLI call fails (not authenticated, item not found, bad WIQL, etc.)."""


def _run_az(args: list[str]) -> str:
    cmd = ["az", *args, "--organization", ORGANIZATION, "--output", "json"]
    result = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8")
    if result.returncode != 0:
        raise BoardsError(result.stderr.strip() or f"az command failed: {' '.join(cmd)}")
    return result.stdout


def get_work_item(work_item_id: int) -> dict:
    """Fetch a single work item's fields (title, description, acceptance criteria, state, etc.)."""
    out = _run_az(["boards", "work-item", "show", "--id", str(work_item_id)])
    return json.loads(out)


def query_work_items(wiql: str) -> list[dict]:
    """Run a WIQL query scoped to this project. Use the literal project name, not @project -
    CLAUDE.md notes @project returns no results here."""
    out = _run_az(["boards", "query", "--wiql", wiql])
    return json.loads(out)


def list_epics() -> list[dict]:
    wiql = (
        f"SELECT [System.Id], [System.Title], [System.State] FROM WorkItems "
        f"WHERE [System.TeamProject] = '{PROJECT}' AND [System.WorkItemType] = 'Epic' "
        f"ORDER BY [System.Id]"
    )
    return query_work_items(wiql)


def list_stories_for_epic(epic_id: int) -> list[dict]:
    wiql = (
        f"SELECT [System.Id], [System.Title], [System.State] FROM WorkItems "
        f"WHERE [System.TeamProject] = '{PROJECT}' AND [System.WorkItemType] = 'Product Backlog Item' "
        f"AND [System.Parent] = {epic_id} ORDER BY [System.Id]"
    )
    return query_work_items(wiql)


def create_epic(title: str, tags: str) -> dict:
    out = _run_az(
        [
            "boards",
            "work-item",
            "create",
            "--project",
            PROJECT,
            "--type",
            "Epic",
            "--title",
            title,
            "--fields",
            f"Microsoft.VSTS.Common.Priority=2",
            "System.Tags=" + tags,
        ]
    )
    return json.loads(out)


def create_story(
    title: str,
    description_html: str,
    acceptance_criteria_html: str,
    tags: str,
    parent_epic_id: int,
) -> dict:
    out = _run_az(
        [
            "boards",
            "work-item",
            "create",
            "--project",
            PROJECT,
            "--type",
            "Product Backlog Item",
            "--title",
            title,
            "--fields",
            "Microsoft.VSTS.Common.Priority=2",
            "System.Description=" + description_html,
            "Microsoft.VSTS.Common.AcceptanceCriteria=" + acceptance_criteria_html,
            "System.Tags=" + tags,
        ]
    )
    created = json.loads(out)
    work_item_id = created["id"]
    _run_az(
        [
            "boards",
            "work-item",
            "relation",
            "add",
            "--id",
            str(work_item_id),
            "--relation-type",
            "parent",
            "--target-id",
            str(parent_epic_id),
        ]
    )
    return created
