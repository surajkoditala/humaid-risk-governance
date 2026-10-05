namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Models.CategoryMapping
{
    /// <summary>Epic 2 - one mapped risk category for an assessment, AI-proposed or analyst-added.</summary>
    public class CategoryMapping
    {
        public Guid Id { get; set; }
        public Guid RiskCategoryId { get; set; }
        public string CategoryCode { get; set; } = string.Empty;
        public string CategoryName { get; set; } = string.Empty;
        public string CitationSection { get; set; } = string.Empty;

        /// <summary>AiProposed | AnalystAdded.</summary>
        public string Source { get; set; } = string.Empty;
        public string? AiCitation { get; set; }
        public bool IsActive { get; set; }

        /// <summary>The reason given for the most recent add/remove of this mapping - read live
        /// from audit_event (never populated when Source is AiProposed and untouched since).</summary>
        public string? AnalystReason { get; set; }
    }

    public class OverrideCategoryMappingInput
    {
        public Guid AssessmentId { get; set; }
        public Guid RiskCategoryId { get; set; }
        public bool IsActive { get; set; }
        public string Reason { get; set; } = string.Empty;
        public Guid ActorUserId { get; set; }
    }
}
