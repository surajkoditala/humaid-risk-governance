namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Ai
{
    /// <summary>What CategoryMappingAiClient (real Claude call, US-2.1) proposes for one category.</summary>
    public class CategoryMappingProposal
    {
        public Guid RiskCategoryId { get; set; }
        public string CategoryCode { get; set; } = string.Empty;
        public string Citation { get; set; } = string.Empty;
        public string Rationale { get; set; } = string.Empty;
    }

    /// <summary>What DocumentExtractionAiClient (real Claude call, US-4.1) extracts for one field.</summary>
    public class ExtractedFieldProposal
    {
        public string FieldKey { get; set; } = string.Empty;
        public string? FieldValue { get; set; }

        /// <summary>0-1. Null/low confidence -> NeedsReview should be true (US-4.1 AC2).</summary>
        public decimal? Confidence { get; set; }
        public bool NeedsReview { get; set; }
        public string? SourceExcerpt { get; set; }
    }

    /// <summary>Input NarrativeDraftingAiClient (real Claude call, US-5.1) is grounded against -
    /// only these facts may be cited; anything else is flagged, never fabricated (US-5.1 AC3).</summary>
    public class NarrativeDraftInput
    {
        public string ChangeType { get; set; } = string.Empty;
        public string ChangeTitle { get; set; } = string.Empty;
        public string ChangeDescription { get; set; } = string.Empty;
        public Guid RiskCategoryId { get; set; }
        public string CategoryName { get; set; } = string.Empty;
        public string CategoryCitation { get; set; } = string.Empty;
        public List<string> ReliedUponPolicyExcerpts { get; set; } = [];
        public List<string> ExtractedFieldFacts { get; set; } = [];

        /// <summary>Analyst guidance for a regeneration pass (US-5.2); null on the first draft.</summary>
        public string? RegenerationFeedback { get; set; }
    }

    public class NarrativeDraftResult
    {
        public string NarrativeText { get; set; } = string.Empty;

        /// <summary>Statements the model could not trace back to <see cref="NarrativeDraftInput"/>'s
        /// supplied facts - surfaced to the analyst, never silently dropped or fabricated.</summary>
        public List<string> UnsupportedClaims { get; set; } = [];
    }
}
