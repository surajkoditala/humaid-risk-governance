"""Document Extraction graph - stub.

Mirrors IDocumentExtractionAiClient / DocumentExtractionAiClient.cs. Every extracted field
must carry a source excerpt and a needsReview flag when confidence is low - see ai/README.md's
citation-fabrication guard before implementing this for real.
"""

from __future__ import annotations

# TODO: define request/response schemas in app/schemas.py, then a StateGraph here, then wire
# a POST /document-extraction route in app/main.py - same shape as category_mapping.py.
