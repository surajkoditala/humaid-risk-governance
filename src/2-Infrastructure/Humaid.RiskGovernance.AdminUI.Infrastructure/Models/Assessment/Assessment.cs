namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Assessment
{
    /// <summary>The FCRM analyst's working record for one change request (see schema/005_assessments.sql).</summary>
    public class Assessment
    {
        public Guid Id { get; set; }
        public Guid ChangeRequestId { get; set; }

        /// <summary>Draft | Finalized.</summary>
        public string Status { get; set; } = string.Empty;
        public Guid? FinalizedByUserId { get; set; }
        public DateTimeOffset? FinalizedAt { get; set; }
    }

    /// <summary>
    /// What's missing before <c>AssessmentService.FinalizeAsync</c> will allow finalization
    /// (US-6.3 AC1: "blocks finalization and lists what's outstanding").
    /// </summary>
    public class AssessmentReadiness
    {
        public bool IsReady => OutstandingNarrativeSections.Count == 0 && CategoriesMissingPolicyReliance.Count == 0;
        public List<string> OutstandingNarrativeSections { get; set; } = [];
        public List<string> CategoriesMissingPolicyReliance { get; set; } = [];
    }
}
