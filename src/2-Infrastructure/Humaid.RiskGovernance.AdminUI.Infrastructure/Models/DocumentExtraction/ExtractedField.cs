namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Models.DocumentExtraction
{
    /// <summary>Epic 4 - one structured fact pulled from a change request's attachments.</summary>
    public class ExtractedField
    {
        public Guid Id { get; set; }
        public string FieldKey { get; set; } = string.Empty;
        public string? FieldValue { get; set; }
        public decimal? Confidence { get; set; }
        public bool NeedsReview { get; set; }
        public string? SourceExcerpt { get; set; }

        /// <summary>AiExtracted | AnalystCorrected.</summary>
        public string Source { get; set; } = string.Empty;
    }

    public class CorrectExtractedFieldInput
    {
        public Guid ChangeRequestId { get; set; }
        public string FieldKey { get; set; } = string.Empty;
        public string NewValue { get; set; } = string.Empty;

        /// <summary>Required only when the edit materially changes the field's meaning (US-4.2) -
        /// that judgment is made by the caller/service, not enforced here.</summary>
        public string? Reason { get; set; }
        public Guid ActorUserId { get; set; }
    }
}
