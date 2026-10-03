"""Standalone dev-tooling LangGraph CLI: checks a local git diff against dev_harness/review-rules.md.

This is NOT part of the shipped product and is never called by the running Workbench. It reuses
ai/langgraph's existing `get_chat_model()` (same ANTHROPIC_API_KEY/.env) purely for convenience,
since that's already configured locally - see harness/README.md for the "why this is separate
from the product AI harness" explanation.

Usage (from repo root):
    cd harness/dev_harness
    python -m harness check                 # review staged + unstaged changes
    python -m harness check --since HEAD~1   # review a specific range
"""
