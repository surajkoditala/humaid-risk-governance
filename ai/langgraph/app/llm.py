"""Chooses which chat model backs the graphs, based on LLM_PROVIDER - mirrors the .NET side's
AI_PROVIDER switch in Program.cs (Anthropic vs AzureFoundry): one place decides the provider,
every graph just gets a LangChain chat model back and doesn't care which one it is.

Supported LLM_PROVIDER values: "anthropic" | "gemini" | "foundry" (foundry not yet implemented
here - the .NET AzureFoundryChatCompletionClient is the reference for that wire format).
"""

from __future__ import annotations

import os

from langchain_core.language_models.chat_models import BaseChatModel


def get_chat_model() -> BaseChatModel:
    provider = os.getenv("LLM_PROVIDER", "gemini").strip().lower()

    if provider == "gemini":
        from langchain_google_genai import ChatGoogleGenerativeAI

        api_key = os.getenv("GOOGLE_API_KEY", "")
        if not api_key:
            raise RuntimeError("GOOGLE_API_KEY must be set when LLM_PROVIDER=gemini.")
        model = os.getenv("GEMINI_MODEL", "gemini-2.0-flash")
        return ChatGoogleGenerativeAI(model=model, google_api_key=api_key)

    if provider == "anthropic":
        from langchain_anthropic import ChatAnthropic

        api_key = os.getenv("ANTHROPIC_API_KEY", "")
        if not api_key:
            raise RuntimeError("ANTHROPIC_API_KEY must be set when LLM_PROVIDER=anthropic.")
        model = os.getenv("ANTHROPIC_MODEL", "")
        if not model:
            raise RuntimeError("ANTHROPIC_MODEL must be set when LLM_PROVIDER=anthropic.")
        return ChatAnthropic(model=model, api_key=api_key)

    raise RuntimeError(
        f"Unsupported LLM_PROVIDER '{provider}'. Supported values: anthropic, gemini."
    )
