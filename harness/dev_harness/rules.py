"""Loads the dev harness's text inputs from disk - review-rules.md and the node prompts under
prompts/ - so every check node grounds itself in the same files a human reads, with no second
copy embedded in Python to drift out of sync.
"""

from __future__ import annotations

from pathlib import Path

_HERE = Path(__file__).resolve().parent
_RULES_PATH = _HERE / "review-rules.md"
_PROMPTS_DIR = _HERE / "prompts"
_SYSTEM_PROMPT_PATH = _PROMPTS_DIR / "system.prompt.md"
_CHECKS_DIR = _PROMPTS_DIR / "checks"
_CHECK_SUFFIX = ".prompt.md"


def load_review_rules() -> str:
    if not _RULES_PATH.exists():
        raise RuntimeError(f"review-rules.md not found at {_RULES_PATH}")
    return _RULES_PATH.read_text(encoding="utf-8")


def load_system_prompt() -> str:
    """The system prompt shared by every check node (output format + 'stay in your lane')."""
    if not _SYSTEM_PROMPT_PATH.exists():
        raise RuntimeError(f"system prompt not found at {_SYSTEM_PROMPT_PATH}")
    return _SYSTEM_PROMPT_PATH.read_text(encoding="utf-8").strip()


def load_check_prompts() -> dict[str, str]:
    """One graph node per prompts/checks/<node_name>.prompt.md; the file name is the node name.

    Adding a check is adding a file here. Fails loudly if none are found, so a bad path can't
    silently produce a harness that reports 'all checks passed' having run nothing.
    """
    paths = sorted(_CHECKS_DIR.glob(f"*{_CHECK_SUFFIX}"))
    if not paths:
        raise RuntimeError(f"no check prompts (*{_CHECK_SUFFIX}) found in {_CHECKS_DIR}")
    return {
        path.name.removesuffix(_CHECK_SUFFIX): path.read_text(encoding="utf-8").strip()
        for path in paths
    }
