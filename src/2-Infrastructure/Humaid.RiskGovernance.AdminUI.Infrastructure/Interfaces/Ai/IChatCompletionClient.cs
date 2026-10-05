namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Ai
{
    /// <summary>
    /// A single chat-completion call against whichever LLM provider is configured - Anthropic
    /// directly, or Azure AI Foundry (see ClaudeApiClient / AzureFoundryChatCompletionClient in
    /// Humaid.RiskGovernance.AdminUI.AI). The three AI-touchpoint clients (category mapping,
    /// document extraction, narrative drafting) depend on this interface rather than a concrete
    /// provider, so the provider is swappable by config (AI_PROVIDER) without touching their
    /// prompts or JSON-parsing logic.
    /// </summary>
    public interface IChatCompletionClient
    {
        Task<string> CompleteAsync(string systemPrompt, string userPrompt, CancellationToken cancellationToken = default);
    }
}
