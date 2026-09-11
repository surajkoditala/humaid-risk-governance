namespace Humaid.RiskGovernance.AdminUI.AI
{
    using System.Net.Http.Json;
    using System.Text.Json;
    using System.Text.Json.Serialization;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Ai;
    using Microsoft.Extensions.Configuration;
    using Microsoft.Extensions.Logging;

    /// <summary>
    /// Thin client for the Azure AI Foundry Model Inference API - the provider the team's
    /// architect and DevOps lead settled on during the 2026-09-09 sync (keeps calls inside Azure,
    /// works against whichever model is deployed to the Foundry project). Its wire contract is
    /// stable regardless of which specific Foundry project is provisioned; only the endpoint,
    /// key, and deployed model name vary per environment (all three come from config, none
    /// hardcoded).
    /// <para>
    /// One of two <see cref="IChatCompletionClient"/> implementations - the other is
    /// <see cref="ClaudeApiClient"/> (the direct-to-Anthropic path used while this Foundry
    /// project didn't exist yet). Selected via <c>AI_PROVIDER=AzureFoundry</c> in
    /// <c>Program.cs</c>; every AI-touchpoint client (category mapping, document extraction,
    /// narrative drafting) is unaffected by the switch - only the JSON message contract and
    /// endpoint differ from <see cref="ClaudeApiClient"/>, not the prompts or response parsing.
    /// </para>
    /// </summary>
    public class AzureFoundryChatCompletionClient : IChatCompletionClient
    {
        private readonly HttpClient _httpClient;
        private readonly string? _model;
        private readonly ILogger<AzureFoundryChatCompletionClient> _logger;

        public AzureFoundryChatCompletionClient(IHttpClientFactory httpClientFactory, IConfiguration configuration, ILogger<AzureFoundryChatCompletionClient> logger)
        {
            _httpClient = httpClientFactory.CreateClient("AzureFoundry");
            _logger = logger;
            _model = configuration["FOUNDRY_MODEL_DEPLOYMENT"];

            var apiKey = configuration["FOUNDRY_API_KEY"];
            if (!string.IsNullOrWhiteSpace(apiKey))
            {
                _httpClient.DefaultRequestHeaders.Add("api-key", apiKey);
            }
        }

        public async Task<string> CompleteAsync(string systemPrompt, string userPrompt, CancellationToken cancellationToken = default)
        {
            if (string.IsNullOrWhiteSpace(_model) || _httpClient.BaseAddress is null || !_httpClient.DefaultRequestHeaders.Contains("api-key"))
            {
                // Same "fail loudly rather than guess silently" rule as ClaudeApiClient (US-2.1
                // AC3) - a misconfigured provider must never look like a quiet no-op.
                throw new InvalidOperationException(
                    "FOUNDRY_PROJECT_ENDPOINT, FOUNDRY_API_KEY, and/or FOUNDRY_MODEL_DEPLOYMENT is not configured - " +
                    "set all three in appsettings.Development.json, or switch AI_PROVIDER back to Anthropic.");
            }

            var request = new FoundryChatRequest
            {
                Model = _model,
                Messages =
                [
                    new FoundryChatMessage { Role = "system", Content = systemPrompt },
                    new FoundryChatMessage { Role = "user", Content = userPrompt },
                ],
            };

            using var response = await _httpClient.PostAsJsonAsync("/models/chat/completions?api-version=2024-05-01-preview", request, cancellationToken);
            var body = await response.Content.ReadAsStringAsync(cancellationToken);

            if (!response.IsSuccessStatusCode)
            {
                _logger.LogError("Azure AI Foundry call failed ({StatusCode}): {Body}", response.StatusCode, body);
                throw new InvalidOperationException($"Azure AI Foundry call failed with {response.StatusCode}.");
            }

            var parsed = JsonSerializer.Deserialize<FoundryChatResponse>(body)
                ?? throw new InvalidOperationException("Azure AI Foundry returned an empty response.");
            var text = parsed.Choices.FirstOrDefault()?.Message?.Content;
            return text ?? throw new InvalidOperationException("Azure AI Foundry response had no message content.");
        }

        private class FoundryChatRequest
        {
            [JsonPropertyName("model")] public string Model { get; set; } = string.Empty;
            [JsonPropertyName("messages")] public List<FoundryChatMessage> Messages { get; set; } = [];
        }

        private class FoundryChatMessage
        {
            [JsonPropertyName("role")] public string Role { get; set; } = string.Empty;
            [JsonPropertyName("content")] public string Content { get; set; } = string.Empty;
        }

        private class FoundryChatResponse
        {
            [JsonPropertyName("choices")] public List<FoundryChatChoice> Choices { get; set; } = [];
        }

        private class FoundryChatChoice
        {
            [JsonPropertyName("message")] public FoundryChatMessage? Message { get; set; }
        }
    }
}
