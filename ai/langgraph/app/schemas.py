"""Pydantic request/response models, mirroring the C# DTOs under
src/2-Infrastructure/Humaid.RiskGovernance.AdminUI.Infrastructure/Models/ so the eventual
.NET HTTP client (LangGraphCategoryMappingAiClient, etc.) is a straight mapping.
"""

from __future__ import annotations

from pydantic import BaseModel


class RiskCategoryOption(BaseModel):
    id: str
    name: str


class CategoryMappingRequest(BaseModel):
    change_request_title: str
    change_request_description: str
    allowed_categories: list[RiskCategoryOption]


class ProposedCategory(BaseModel):
    category_id: str
    rationale: str


class CategoryMappingResponse(BaseModel):
    proposed_categories: list[ProposedCategory]
