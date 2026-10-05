"""CLI entrypoint: `python -m harness check [--since REF]`.

Run from harness/dev_harness/ using ai/langgraph's existing venv (same dependencies - langgraph,
langchain-anthropic - already installed there; see harness/dev_harness/README.md).
"""

from __future__ import annotations

import argparse
import sys

from .diff_source import get_diff
from .graph import run_harness


def main() -> int:
    parser = argparse.ArgumentParser(prog="dev-harness")
    subparsers = parser.add_subparsers(dest="command", required=True)

    check_parser = subparsers.add_parser("check", help="Review a local diff against dev_harness/review-rules.md")
    check_parser.add_argument(
        "--since",
        default=None,
        help="Git ref to diff against (e.g. HEAD~1, main). Defaults to working tree vs HEAD.",
    )
    check_parser.add_argument(
        "--out",
        default=None,
        help="Write the report to this file instead of only printing it.",
    )

    check_parser.add_argument(
        "--max-diff-bytes",
        type=int,
        default=None,
        help="Truncate the diff sent to the model to this many bytes (CI uses this as a cost guard).",
    )

    args = parser.parse_args()

    if args.command == "check":
        diff = get_diff(args.since, args.max_diff_bytes)
        report = run_harness(diff)
        print(report)
        if args.out:
            from pathlib import Path

            Path(args.out).write_text(report, encoding="utf-8")
            print(f"\n(also written to {args.out})")
        return 0

    return 1


if __name__ == "__main__":
    sys.exit(main())
