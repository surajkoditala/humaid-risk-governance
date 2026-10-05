"""Loads ba_harness/writing-standards.md once, so every check node grounds its prompt in the
same text a human BA would read - mirrors dev_harness/rules.py's single-source-of-truth pattern.
"""

from __future__ import annotations

from pathlib import Path

_STANDARDS_PATH = Path(__file__).resolve().parent / "writing-standards.md"


def load_writing_standards() -> str:
    if not _STANDARDS_PATH.exists():
        raise FileNotFoundError(
            f"Expected writing standards at {_STANDARDS_PATH}, but it does not exist."
        )
    return _STANDARDS_PATH.read_text(encoding="utf-8")
