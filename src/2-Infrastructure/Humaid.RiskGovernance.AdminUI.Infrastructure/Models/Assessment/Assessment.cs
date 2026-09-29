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
        // DEF-001: an assessment with zero mapped categories used to pass vacuously - both lists
        // below start (and stay) empty, so nothing looked outstanding. NoCategoriesMapped and
        // CategoriesMissingScore close that: "nothing to review" is not the same as "reviewed."
        public bool IsReady => !NoCategoriesMapped && OutstandingNarrativeSections.Count == 0
            && CategoriesMissingPolicyReliance.Count == 0 && CategoriesMissingScore.Count == 0;
        public bool NoCategoriesMapped { get; set; }
        public List<string> OutstandingNarrativeSections { get; set; } = [];
        public List<string> CategoriesMissingPolicyReliance { get; set; } = [];
        public List<string> CategoriesMissingScore { get; set; } = [];
    }
}
