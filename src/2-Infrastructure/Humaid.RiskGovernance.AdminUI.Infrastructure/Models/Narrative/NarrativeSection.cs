namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Narrative
{
    /// <summary>Epic 5 - one risk category's narrative within an assessment.</summary>
    public class NarrativeSection
    {
        public Guid Id { get; set; }
        public Guid RiskCategoryId { get; set; }
        public string CategoryName { get; set; } = string.Empty;
        public string NarrativeText { get; set; } = string.Empty;

        /// <summary>AiDrafted | AnalystReviewed | AnalystEdited.</summary>
        public string Status { get; set; } = string.Empty;

        /// <summary>Claims NarrativeDraftingAiClient could not trace to a supplied source (US-5.1 AC3).</summary>
        public string UnsupportedClaimFlagsJson { get; set; } = "[]";
    }

    public class EditNarrativeSectionInput
    {
        public Guid AssessmentId { get; set; }
        public Guid RiskCategoryId { get; set; }
        public string NewText { get; set; } = string.Empty;
        public string Reason { get; set; } = string.Empty;
        public Guid ActorUserId { get; set; }
    }
}
