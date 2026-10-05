"""Standalone dev-tooling LangGraph CLI: reviews, validates, and creates epics/stories in Azure
Boards against ba_harness/writing-standards.md.

This is NOT part of the shipped product and is never called by the running Workbench. It reuses
ai/langgraph's existing get_chat_model() (same ANTHROPIC_API_KEY/.env) purely for convenience,
and the already-authenticated `az devops` CLI session for Boards access - see
harness/ba_harness/README.md for usage and harness/README.md for the "why this is separate" note.
"""
