"""FastAPI entrypoint for the LangGraph orchestration service.

One route per AI touchpoint (see ai/langgraph/README.md). Each route wraps a LangGraph
graph under app/graphs/ - kept as separate graphs (not one shared graph) because the three
touchpoints have independent inputs/outputs on the .NET side (ICategoryMappingAiClient,
IDocumentExtractionAiClient, INarrativeDraftingAiClient) and are called independently.
"""

from __future__ import annotations

from dotenv import load_dotenv
from fastapi import FastAPI

load_dotenv()

from app.schemas import (  # noqa: E402 - must load .env (above) before app.llm reads env vars
    CategoryMappingRequest,
    CategoryMappingResponse,
)

app = FastAPI(title="Humaid Risk Governance - LangGraph Orchestration")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/category-mapping", response_model=CategoryMappingResponse)
def category_mapping(request: CategoryMappingRequest) -> CategoryMappingResponse:
    from app.graphs.category_mapping import run_category_mapping

    return run_category_mapping(request)


# /document-extraction and /narrative-drafting follow the same shape once their graphs
# and schemas are filled in - see app/graphs/document_extraction.py and
# app/graphs/narrative_drafting.py (stubs).
