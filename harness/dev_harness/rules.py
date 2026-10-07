"""Loads dev_harness/review-rules.md once, so every check node grounds its prompt in the same
text the human reviewer reads - no separate copy of the rules to drift out of sync.
"""

from __future__ import annotations

from pathlib import Path

_RULES_PATH = Path(__file__).resolve().parent / "review-rules.md"


def load_review_rules() -> str:
    if not _RULES_PATH.exists():
        raise RuntimeError(f"review-rules.md not found at {_RULES_PATH}")
    return _RULES_PATH.read_text(encoding="utf-8")
