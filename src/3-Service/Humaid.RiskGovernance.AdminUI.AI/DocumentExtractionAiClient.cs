namespace Humaid.RiskGovernance.AdminUI.AI
{
    using System.Text.Json;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Ai;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Ai;

    /// <summary>US-4.1. Prompt mirrored at /ai/prompts/document-extraction.md - keep the two in sync.</summary>
    public class DocumentExtractionAiClient : IDocumentExtractionAiClient
    {
        private const string SystemPrompt = """
            You are extracting structured facts from a document attached to a bank's financial
            crime risk change request. Extract only facts you can find verbatim or near-verbatim in
            the supplied document text - never infer or guess a value that is not actually stated.

            For a Vendor change, look for fields like vendor_name, vendor_jurisdiction,
            data_access_scope. For a Geography change, look for target_country, target_region. For
            other change types, extract whatever concrete facts (customer types affected, data
            flows, transaction types) are actually present in the text.

            For each field: if you are not confident (the text is ambiguous, partial, or you had to
            infer rather than read it directly), set "needsReview": true and lower "confidence"
            accordingly - do not silently guess a confident-looking value.

            Respond with ONLY a JSON array, no prose, no markdown fences. Each element:
              {"fieldKey": "<snake_case_key>", "fieldValue": "<value or null>", "confidence": <0-1 or null>, "needsReview": <bool>, "sourceExcerpt": "<short verbatim quote it came from, or null>"}
            """;

        private readonly IChatCompletionClient _chatCompletionClient;

        public DocumentExtractionAiClient(IChatCompletionClient chatCompletionClient)
        {
            _chatCompletionClient = chatCompletionClient;
        }

        public async Task<IReadOnlyList<ExtractedFieldProposal>> ExtractAsync(
            string changeType, string documentText, CancellationToken cancellationToken = default)
        {
            if (string.IsNullOrWhiteSpace(documentText))
                return [];

            var userPrompt = $"Change type: {changeType}\n\nDocument text:\n{documentText}";
            var raw = await _chatCompletionClient.CompleteAsync(SystemPrompt, userPrompt, cancellationToken);
            var json = JsonExtraction.ExtractJson(raw);

            try
            {
                return JsonSerializer.Deserialize<List<ExtractedFieldProposal>>(json, JsonExtraction.CaseInsensitive) ?? [];
            }
            catch (JsonException)
            {
                return [];
            }
        }
    }
}
