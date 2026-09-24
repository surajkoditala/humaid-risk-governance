namespace Humaid.RiskGovernance.AdminUI.AI
{
    using System.Net.Http.Headers;
    using System.Net.Http.Json;
    using System.Text.Json;
    using System.Text.Json.Serialization;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Ai;
    using Microsoft.Extensions.Configuration;
    using Microsoft.Extensions.Logging;

    /// <summary>
    /// Thin client for Anthropic's Messages API - one explicit client per external dependency,
    /// no SDK wrapper. A handful of well-known REST calls don't need one.
    /// <para>
    /// <c>ANTHROPIC_MODEL</c> has no hardcoded fallback deliberately - shipping a guessed or
    /// stale model ID is worse than failing loudly the first time an AI endpoint is actually
    /// called. Set both <c>ANTHROPIC_API_KEY</c> and <c>ANTHROPIC_MODEL</c> in
    /// appsettings.Development.json (check Anthropic's current model list for the latter).
    /// </para>
    /// <para>
    /// One of two <see cref="IChatCompletionClient"/> implementations - the other is
    /// <see cref="AzureFoundryChatCompletionClient"/>. Which one the three AI-touchpoint clients
    /// actually receive is decided by <c>AI_PROVIDER</c> in <c>Program.cs</c>, not here.
    /// </para>
    /// </summary>
    public class ClaudeApiClient : IChatCompletionClient
    {
        private readonly HttpClient _httpClient;
        private readonly string? _model;
        private readonly bool _isConfigured;
        private readonly ILogger<ClaudeApiClient> _logger;

        public ClaudeApiClient(IHttpClientFactory httpClientFactory, IConfiguration configuration, ILogger<ClaudeApiClient> logger)
        {
            _httpClient = httpClientFactory.CreateClient("AnthropicApi");
            _logger = logger;
            _model = configuration["ANTHROPIC_MODEL"];

            var apiKey = configuration["ANTHROPIC_API_KEY"];
            _isConfigured = !string.IsNullOrWhiteSpace(apiKey);
            if (_isConfigured)
            {
                // Two different credential shapes share this one config key: a standard API key
                // (sk-ant-api03-...) authenticates via the x-api-key header; a Claude Code/Claude
                // Agent SDK long-lived OAuth token (sk-ant-oat01-..., from `claude setup-token`,
                // tied to a Pro/Max subscription rather than API billing) only authenticates via
                // Authorization: Bearer - x-api-key returns 401 "API key is invalid" for it, even
                // though the token itself is valid (confirmed against the real endpoint).
                if (apiKey!.StartsWith("sk-ant-oat", StringComparison.Ordinal))
                {
                    _httpClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);
                }
                else
                {
                    _httpClient.DefaultRequestHeaders.Add("x-api-key", apiKey);
                }
            }
            _httpClient.DefaultRequestHeaders.Add("anthropic-version", "2023-06-01");
        }

        public async Task<string> CompleteAsync(string systemPrompt, string userPrompt, CancellationToken cancellationToken = default)
        {
            if (string.IsNullOrWhiteSpace(_model) || !_isConfigured)
            {
                // Every other AI touchpoint in this app flags missing configuration explicitly
                // rather than silently guessing (US-2.1 AC3) - the same rule applies here.
                throw new InvalidOperationException(
                    "ANTHROPIC_API_KEY and/or ANTHROPIC_MODEL is not configured - set both in appsettings.Development.json.");
            }

            var request = new ClaudeRequest
            {
                Model = _model,
                MaxTokens = 4096,
                System = systemPrompt,
                Messages = [new ClaudeMessage { Role = "user", Content = userPrompt }],
            };

            using var response = await _httpClient.PostAsJsonAsync("/v1/messages", request, cancellationToken);
            var body = await response.Content.ReadAsStringAsync(cancellationToken);

            if (!response.IsSuccessStatusCode)
            {
                _logger.LogError("Anthropic API call failed ({StatusCode}): {Body}", response.StatusCode, body);
                throw new InvalidOperationException($"Anthropic API call failed with {response.StatusCode}.");
            }

            var parsed = JsonSerializer.Deserialize<ClaudeResponse>(body)
                ?? throw new InvalidOperationException("Anthropic API returned an empty response.");
            var text = parsed.Content.FirstOrDefault(c => c.Type == "text")?.Text;
            return text ?? throw new InvalidOperationException("Anthropic API response had no text content block.");
        }

        private class ClaudeRequest
        {
            [JsonPropertyName("model")] public string Model { get; set; } = string.Empty;
            [JsonPropertyName("max_tokens")] public int MaxTokens { get; set; }
            [JsonPropertyName("system")] public string System { get; set; } = string.Empty;
            [JsonPropertyName("messages")] public List<ClaudeMessage> Messages { get; set; } = [];
        }

        private class ClaudeMessage
        {
            [JsonPropertyName("role")] public string Role { get; set; } = string.Empty;
            [JsonPropertyName("content")] public string Content { get; set; } = string.Empty;
        }

        private class ClaudeResponse
        {
            [JsonPropertyName("content")] public List<ClaudeContentBlock> Content { get; set; } = [];
        }

        private class ClaudeContentBlock
        {
            [JsonPropertyName("type")] public string Type { get; set; } = string.Empty;
            [JsonPropertyName("text")] public string? Text { get; set; }
        }
    }
}
