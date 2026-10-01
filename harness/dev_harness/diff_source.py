"""Wraps `git diff` so the harness only ever sends the actual changed lines to the model -
never the whole repo - matching this project's own AI clients being grounded on fixed, supplied
input rather than an open-ended context dump.
"""

from __future__ import annotations

import subprocess


def get_diff(since: str | None) -> str:
    if since:
        cmd = ["git", "diff", since]
    else:
        # Staged + unstaged working-tree changes - what you're about to commit or amend.
        cmd = ["git", "diff", "HEAD"]

    result = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        raise RuntimeError(f"git diff failed: {result.stderr.strip()}")
    return result.stdout
