namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Models.AiUsage
{
    /// <summary>
    /// Measured token use - one append-only <c>ai_call_log</c> row: a successful call to the AI
    /// provider and the token counts the provider reported for it. See schema/016_ai_call_log.sql.
    /// A token count is null when the provider did not report it - never 0.
    /// </summary>
    public class AiCall
    {
        public Guid Id { get; set; }
        public Guid? ChangeRequestId { get; set; }
        public Guid? AssessmentId { get; set; }

        /// <summary>The Workbench step: category_mapping, document_extraction or narrative_drafting.</summary>
        public string Operation { get; set; } = string.Empty;

        /// <summary>anthropic or az.ai.inference.</summary>
        public string Provider { get; set; } = string.Empty;
        public string? Model { get; set; }
        public long? InputTokens { get; set; }
        public long? OutputTokens { get; set; }
        public long? CacheReadTokens { get; set; }
        public long? CacheCreationTokens { get; set; }
        public int? DurationMs { get; set; }
        public DateTimeOffset CreatedAt { get; set; }
    }

    public class LogAiCallInput
    {
        public Guid? ChangeRequestId { get; set; }
        public Guid? AssessmentId { get; set; }
        public string Operation { get; set; } = string.Empty;
        public string Provider { get; set; } = string.Empty;
        public string? Model { get; set; }
        public long? InputTokens { get; set; }
        public long? OutputTokens { get; set; }
        public long? CacheReadTokens { get; set; }
        public long? CacheCreationTokens { get; set; }
        public int? DurationMs { get; set; }
    }

    /// <summary>Every recorded AI call for one change request, with the totals a reviewer wants first.</summary>
    public class AiUsageForRequest
    {
        public IReadOnlyList<AiCall> Calls { get; set; } = [];
        public int CallCount { get; set; }

        /// <summary>Sums skip a null count rather than treating it as 0, so they can only under-report.</summary>
        public long InputTokens { get; set; }
        public long OutputTokens { get; set; }
        public long CacheReadTokens { get; set; }
        public long CacheCreationTokens { get; set; }
        public IReadOnlyList<AiUsageByOperation> ByOperation { get; set; } = [];
    }

    public class AiUsageByOperation
    {
        public string Operation { get; set; } = string.Empty;
        public int Calls { get; set; }
        public long InputTokens { get; set; }
        public long OutputTokens { get; set; }
    }
}
