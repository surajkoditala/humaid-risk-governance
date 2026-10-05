"""CLI entrypoint for the BA harness.

Commands:
    python -m ba_harness review --id <work_item_id>       Review an existing Boards item
    python -m ba_harness review --file <path>              Review a drafted epic/story from a file
    python -m ba_harness create --file <path> --epic <id>  Validate a draft, then create it in
                                                             Boards as a child of --epic (omit
                                                             --epic when creating an Epic itself)
    python -m ba_harness list-epics                         List all epics currently in Boards
    python -m ba_harness list-stories --epic <id>           List all stories under an epic

Requires an active `az devops login` session (see CLAUDE.md's "Azure DevOps Boards" section) -
this tool never prompts for or stores a PAT itself.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from . import boards_client
from .graph import run_extract, run_review


def _read_item_text(args: argparse.Namespace) -> str:
    if args.id:
        item = boards_client.get_work_item(args.id)
        fields = item.get("fields", {})
        parts = [
            f"Title: {fields.get('System.Title', '')}",
            f"Type: {fields.get('System.WorkItemType', '')}",
            f"Description: {fields.get('System.Description', '')}",
            f"Acceptance Criteria: {fields.get('Microsoft.VSTS.Common.AcceptanceCriteria', '')}",
            f"Tags: {fields.get('System.Tags', '')}",
        ]
        return "\n".join(parts)
    if args.file:
        return Path(args.file).read_text(encoding="utf-8")
    raise SystemExit("review requires either --id or --file")


def _cmd_review(args: argparse.Namespace) -> int:
    item_text = _read_item_text(args)
    print(run_review(item_text))
    return 0


def _cmd_create(args: argparse.Namespace) -> int:
    draft_text = Path(args.file).read_text(encoding="utf-8")

    print("Reviewing draft against writing standards before creating...\n")
    review = run_review(draft_text)
    print(review)
    if "Needs changes" in review and not args.force:
        print(
            "\nDraft needs changes before it can be created. Re-run with --force to create "
            "anyway, or fix the draft and re-run."
        )
        return 1

    extracted = run_extract(draft_text)
    print("\nExtracted fields:")
    print(extracted)

    if extracted.get("is_ai_touchpoint") and extracted.get("needs_human_review_pair"):
        print(
            "\nWARNING: this is an [AI] story with no paired human-review story mentioned in "
            "the draft. Per writing-standards.md, add that pairing before/after creating this."
        )
        if not args.force:
            return 1

    if extracted["work_item_type"] == "Epic":
        created = boards_client.create_epic(extracted["title"], extracted["tags"])
    else:
        if not args.epic:
            raise SystemExit("creating a Story requires --epic <parent epic id>")
        created = boards_client.create_story(
            title=extracted["title"],
            description_html=extracted["description_html"],
            acceptance_criteria_html=extracted["acceptance_criteria_html"],
            tags=extracted["tags"],
            parent_epic_id=args.epic,
        )

    print(f"\nCreated work item {created['id']}: {extracted['title']}")
    print(
        "Remember: mirror this into docs/requirements/user-stories.md so the IDs stay in sync "
        "(see CLAUDE.md's 'Keep the docs in sync' rule)."
    )
    return 0


def _cmd_list_epics(args: argparse.Namespace) -> int:
    for epic in boards_client.list_epics():
        fields = epic.get("fields", epic)
        print(f"{epic.get('id', fields.get('System.Id'))}: {fields.get('System.Title')}")
    return 0


def _cmd_list_stories(args: argparse.Namespace) -> int:
    for story in boards_client.list_stories_for_epic(args.epic):
        fields = story.get("fields", story)
        print(f"{story.get('id', fields.get('System.Id'))}: {fields.get('System.Title')}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(prog="ba-harness")
    subparsers = parser.add_subparsers(dest="command", required=True)

    review_parser = subparsers.add_parser("review", help="Review an existing or drafted epic/story")
    review_parser.add_argument("--id", type=int, default=None, help="Existing Boards work item ID")
    review_parser.add_argument("--file", default=None, help="Path to a drafted epic/story text file")

    create_parser = subparsers.add_parser(
        "create", help="Validate a draft and create it in Boards"
    )
    create_parser.add_argument("--file", required=True, help="Path to a drafted epic/story text file")
    create_parser.add_argument(
        "--epic", type=int, default=None, help="Parent epic ID (required when creating a Story)"
    )
    create_parser.add_argument(
        "--force", action="store_true", help="Create even if review found issues or the [AI] pairing is missing"
    )

    subparsers.add_parser("list-epics", help="List all epics in Boards")

    list_stories_parser = subparsers.add_parser("list-stories", help="List all stories under an epic")
    list_stories_parser.add_argument("--epic", type=int, required=True)

    args = parser.parse_args()

    if args.command == "review":
        return _cmd_review(args)
    if args.command == "create":
        return _cmd_create(args)
    if args.command == "list-epics":
        return _cmd_list_epics(args)
    if args.command == "list-stories":
        return _cmd_list_stories(args)
    return 1


if __name__ == "__main__":
    sys.exit(main())
