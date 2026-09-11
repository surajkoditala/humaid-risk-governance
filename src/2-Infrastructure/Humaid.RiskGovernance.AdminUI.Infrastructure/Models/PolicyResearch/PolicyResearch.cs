namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Models.PolicyResearch
{
    /// <summary>
    /// Epic 3 - one ranked hit from func_searchPolicyChunks. Deterministic full-text search, not
    /// an LLM call - see docs/governance/human-in-the-loop-gates.md.
    /// </summary>
    public class PolicyChunkSearchResult
    {
        public Guid Id { get; set; }
        public Guid PolicyDocumentId { get; set; }
        public string DocumentTitle { get; set; } = string.Empty;
        public string SourceUrl { get; set; } = string.Empty;

        /// <summary>Postgres `date` column - kept as DateTime (Dapper/Npgsql map it directly) rather
        /// than DateOnly, which needs a custom Dapper type handler to avoid an InvalidCastException.</summary>
        public DateTime? EffectiveDate { get; set; }
        public string SectionRef { get; set; } = string.Empty;
        public string ChunkText { get; set; } = string.Empty;
        public float Rank { get; set; }
    }

    public class PolicyReliance
    {
        public Guid Id { get; set; }
        public Guid? RiskCategoryId { get; set; }
        public Guid PolicyChunkId { get; set; }

        /// <summary>ReliedUpon | NotRelevant.</summary>
        public string Decision { get; set; } = string.Empty;
        public string SectionRef { get; set; } = string.Empty;
        public string ChunkText { get; set; } = string.Empty;
    }

    public class RecordPolicyRelianceInput
    {
        public Guid AssessmentId { get; set; }
        public Guid? RiskCategoryId { get; set; }
        public Guid PolicyChunkId { get; set; }
        public string Decision { get; set; } = string.Empty;
        public Guid DecidedByUserId { get; set; }
    }
}
