namespace Humaid.RiskGovernance.AdminUI.AI
{
    using System.Text.Json;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Ai;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Ai;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.RiskFramework;

    /// <summary>US-2.1. Prompt mirrored at /ai/prompts/category-mapping.md - keep the two in sync.</summary>
    public class CategoryMappingAiClient : ICategoryMappingAiClient
    {
        private const string SystemPrompt = """
            You are a Financial Crimes Risk Management (FCRM) analyst assistant for a bank. Given a
            proposed business change and a fixed list of allowed risk categories (drawn from the
            FFIEC BSA/AML Examination Manual), propose which of those categories apply.

            Rules:
            - Only choose from the supplied list of categories - never invent a category or citation
              that is not in that list.
            - For each category you propose, give a one-sentence rationale grounded in the change's
              own title/description.
            - Respond with ONLY a JSON array, no prose, no markdown fences. Each element:
              {"riskCategoryId": "<uuid from the supplied list>", "rationale": "<one sentence>"}
            """;

        private readonly IChatCompletionClient _chatCompletionClient;

        public CategoryMappingAiClient(IChatCompletionClient chatCompletionClient)
        {
            _chatCompletionClient = chatCompletionClient;
        }

        public async Task<IReadOnlyList<CategoryMappingProposal>> ProposeAsync(
            string changeType,
            string title,
            string description,
            IReadOnlyList<ChangeTypeCategoryDefault> defaults,
            string? externalContextSummary = null,
            CancellationToken cancellationToken = default)
        {
            if (defaults.Count == 0)
            {
                // US-2.1 AC3: flag explicitly (empty result) rather than guessing silently when no
                // framework mapping is configured for this change type.
                return [];
            }

            // Phase 3 - Data Ingestion Layer grounding (optional): when the change request links a
            // Mock Systems customer/product/vendor, that snapshot's risk-context fields are added
            // as extra grounding, same as CategoryMappingService builds it. Change types with no
            // linked entity (or when Mock Systems was unreachable at intake) fall back to today's
            // change-type-only prompt - this must never be the only path, since not every change
            // type has an obvious entity to link.
            var externalContextBlock = string.IsNullOrWhiteSpace(externalContextSummary)
                ? string.Empty
                : $"\n\nLinked external context (from the bank's own systems, for additional grounding only - do not treat this as a category or a citation):\n{externalContextSummary}";

            var userPrompt = $$"""
                Change type: {{changeType}}
                Title: {{title}}
                Description: {{description}}{{externalContextBlock}}

                Allowed categories (JSON):
                {{JsonSerializer.Serialize(defaults)}}
                """;

            var raw = await _chatCompletionClient.CompleteAsync(SystemPrompt, userPrompt, cancellationToken);
            var json = JsonExtraction.ExtractJson(raw);

            List<ClaudeCategoryProposal>? parsed;
            try
            {
                parsed = JsonSerializer.Deserialize<List<ClaudeCategoryProposal>>(json, JsonExtraction.CaseInsensitive);
            }
            catch (JsonException)
            {
                return [];
            }
            if (parsed is null) return [];

            var byId = defaults.ToDictionary(d => d.RiskCategoryId);
            var result = new List<CategoryMappingProposal>();
            foreach (var proposal in parsed)
            {
                // Never fabricates a citation: a category ID we didn't supply is dropped, not
                // passed through (US-2.1's grounding requirement).
                if (!Guid.TryParse(proposal.RiskCategoryId, out var categoryId) || !byId.TryGetValue(categoryId, out var matched))
                    continue;

                result.Add(new CategoryMappingProposal
                {
                    RiskCategoryId = categoryId,
                    CategoryCode = matched.Code,
                    Citation = matched.CitationSection,
                    Rationale = proposal.Rationale ?? string.Empty,
                });
            }

            // DEF-012: the model's inclusion of the deterministic change-type -> category mapping
            // from CLAUDE.md (e.g. Vendor onboarding -> Customers/Entities + Delivery Channels) was
            // left entirely to the model's judgment, so a category with Weight="Primary" would
            // sometimes not appear across otherwise-identical requests. Add back any Primary
            // category the model's own response omitted - deterministically, not model-generated -
            // so the baseline mapping is guaranteed regardless of what the model chose to include.
            var proposedIds = result.Select(r => r.RiskCategoryId).ToHashSet();
            foreach (var primary in defaults.Where(d => d.Weight == "Primary" && !proposedIds.Contains(d.RiskCategoryId)))
            {
                result.Add(new CategoryMappingProposal
                {
                    RiskCategoryId = primary.RiskCategoryId,
                    CategoryCode = primary.Code,
                    Citation = primary.CitationSection,
                    Rationale = $"Deterministically required for a {changeType} change per the documented FFIEC change-type mapping.",
                });
            }

            return result;
        }

        private class ClaudeCategoryProposal
        {
            public string? RiskCategoryId { get; set; }
            public string? Rationale { get; set; }
        }
    }
}
