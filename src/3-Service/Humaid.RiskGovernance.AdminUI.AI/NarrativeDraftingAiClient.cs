namespace Humaid.RiskGovernance.AdminUI.AI
{
    using System.Text;
    using System.Text.Json;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Ai;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Ai;

    /// <summary>US-5.1/US-5.2. Prompt mirrored at /ai/prompts/narrative-drafting.md - keep the two in sync.</summary>
    public class NarrativeDraftingAiClient : INarrativeDraftingAiClient
    {
        private const string SystemPrompt = """
            You are drafting one risk category's narrative for a bank's Financial Crimes Risk
            Management (FCRM) assessment of a proposed business change. You are given: the change
            details, the risk category and its supervisory citation, policy excerpts the analyst has
            already marked as relied-upon, and facts extracted from submitted documents.

            Rules:
            - Cite ONLY the policy excerpts and extracted facts you were given - never invent a
              citation, a fact, or a source that was not supplied to you.
            - If you would naturally want to make a claim that is NOT supported by the supplied
              material, do not state it as fact - list it in "unsupportedClaims" instead and leave
              it out of the narrative text.
            - Write 2-4 paragraphs, professional FCRM tone, referencing the supplied policy
              citations by their section reference.
            - If "regenerationFeedback" is supplied at the end of the input, revise according to
              that feedback rather than starting the narrative over conceptually.

            Respond with ONLY a JSON object, no prose, no markdown fences:
              {"narrativeText": "<the narrative>", "unsupportedClaims": ["<claim 1>", ...]}
            """;

        private readonly IChatCompletionClient _chatCompletionClient;

        public NarrativeDraftingAiClient(IChatCompletionClient chatCompletionClient)
        {
            _chatCompletionClient = chatCompletionClient;
        }

        public async Task<NarrativeDraftResult> DraftAsync(NarrativeDraftInput input, CancellationToken cancellationToken = default)
        {
            var prompt = new StringBuilder();
            prompt.AppendLine($"Change type: {input.ChangeType}");
            prompt.AppendLine($"Title: {input.ChangeTitle}");
            prompt.AppendLine($"Description: {input.ChangeDescription}");
            prompt.AppendLine($"Risk category: {input.CategoryName} (citation: {input.CategoryCitation})");

            prompt.AppendLine("Relied-upon policy excerpts:");
            foreach (var excerpt in input.ReliedUponPolicyExcerpts)
                prompt.AppendLine($"- {excerpt}");

            prompt.AppendLine("Extracted document facts:");
            foreach (var fact in input.ExtractedFieldFacts)
                prompt.AppendLine($"- {fact}");

            if (!string.IsNullOrWhiteSpace(input.RegenerationFeedback))
                prompt.AppendLine($"regenerationFeedback: {input.RegenerationFeedback}");

            var raw = await _chatCompletionClient.CompleteAsync(SystemPrompt, prompt.ToString(), cancellationToken);
            var json = JsonExtraction.ExtractJson(raw);

            try
            {
                return JsonSerializer.Deserialize<NarrativeDraftResult>(json, JsonExtraction.CaseInsensitive)
                    ?? UnparseableResult();
            }
            catch (JsonException)
            {
                return UnparseableResult();
            }
        }

        private static NarrativeDraftResult UnparseableResult() => new()
        {
            NarrativeText = string.Empty,
            UnsupportedClaims = ["The AI response could not be parsed - see logs; draft manually or retry."],
        };
    }
}
