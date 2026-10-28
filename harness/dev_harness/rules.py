"""Loads the dev harness's text inputs from disk - review-rules.md and the node prompts under
prompts/ - so every check node grounds itself in the same files a human reads, with no second
copy embedded in Python to drift out of sync.
"""

from __future__ import annotations

import re
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


# A check prompt may start with `<!-- applies-to: <regex> -->`. The check then only runs when at
# least one changed file path matches the regex (re.search); otherwise it is skipped without a
# model call. No directive means the check runs on every diff.
_SCOPE_DIRECTIVE = re.compile(r"\A<!--\s*applies-to:\s*(.+?)\s*-->\s*", re.DOTALL)


def _read_check_files() -> dict[str, str]:
    paths = sorted(_CHECKS_DIR.glob(f"*{_CHECK_SUFFIX}"))
    if not paths:
        raise RuntimeError(f"no check prompts (*{_CHECK_SUFFIX}) found in {_CHECKS_DIR}")
    return {path.name.removesuffix(_CHECK_SUFFIX): path.read_text(encoding="utf-8").strip() for path in paths}


def load_check_prompts() -> dict[str, str]:
    """One graph node per prompts/checks/<node_name>.prompt.md; the file name is the node name.

    Adding a check is adding a file here. Fails loudly if none are found, so a bad path can't
    silently produce a harness that reports 'all checks passed' having run nothing. The optional
    applies-to directive is stripped; see load_check_scopes().
    """
    return {name: _SCOPE_DIRECTIVE.sub("", text, count=1) for name, text in _read_check_files().items()}


def load_check_scopes() -> dict[str, re.Pattern[str]]:
    """The applies-to pattern for each check that declares one (checks without one always run)."""
    scopes: dict[str, re.Pattern[str]] = {}
    for name, text in _read_check_files().items():
        match = _SCOPE_DIRECTIVE.match(text)
        if match:
            scopes[name] = re.compile(match.group(1))  # an invalid pattern fails loudly at import
    return scopes
