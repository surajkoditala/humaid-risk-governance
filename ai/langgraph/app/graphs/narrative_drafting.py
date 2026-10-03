"""Narrative Drafting graph - stub.

Mirrors INarrativeDraftingAiClient / NarrativeDraftingAiClient.cs. Any statement the model
can't support from the supplied categories/facts/policy excerpts must come back in a separate
unsupported_claims list, never folded into the narrative text - see ai/README.md.
"""

from __future__ import annotations

# TODO: define request/response schemas in app/schemas.py, then a StateGraph here, then wire
# a POST /narrative-drafting route in app/main.py - same shape as category_mapping.py.
