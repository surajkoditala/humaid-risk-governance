"""Wraps `git diff` so the harness only ever sends the actual changed lines to the model -
never the whole repo - matching this project's own AI clients being grounded on fixed, supplied
input rather than an open-ended context dump.
"""

from __future__ import annotations

import subprocess


def get_diff(since: str | None, max_bytes: int | None = None) -> str:
    if since:
        cmd = ["git", "diff", since]
    else:
        # Staged + unstaged working-tree changes - what you're about to commit or amend.
        cmd = ["git", "diff", "HEAD"]

    # Decode as UTF-8 explicitly: the Windows default (cp1252) crashes on any non-ASCII byte in the diff.
    result = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", check=False)
    if result.returncode != 0:
        raise RuntimeError(f"git diff failed: {result.stderr.strip()}")

    diff = result.stdout
    encoded = diff.encode("utf-8")
    if max_bytes is not None and len(encoded) > max_bytes:
        # Cost guard (CI passes this): every check node receives the whole diff, so cap it. The
        # tail is dropped, and the diff itself says so, so the reviewing checks can surface it.
        diff = encoded[:max_bytes].decode("utf-8", errors="ignore")
        diff += f"\n\n[... diff truncated to {max_bytes} bytes; files after this point were NOT reviewed ...]\n"
    return diff
