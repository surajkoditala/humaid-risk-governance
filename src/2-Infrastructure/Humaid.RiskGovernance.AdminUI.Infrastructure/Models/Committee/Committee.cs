namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Committee
{
    /// <summary>Epic 8 - one entry in the committee's decision queue (US-8.1).</summary>
    public class CommitteeQueueItem
    {
        public Guid AssessmentId { get; set; }
        public Guid ChangeRequestId { get; set; }
        public string RequestNumber { get; set; } = string.Empty;
        public string ChangeType { get; set; } = string.Empty;
        public string Title { get; set; } = string.Empty;
        public DateTimeOffset RoutedAt { get; set; }
    }

    /// <summary>One committee member's individual, never-aggregated vote (US-8.2 AC5).</summary>
    public class CommitteeVote
    {
        public Guid Id { get; set; }
        public Guid CommitteeMemberUserId { get; set; }
        public string CommitteeMemberName { get; set; } = string.Empty;

        /// <summary>Approve | Reject | Defer | ApproveWithConditions.</summary>
        public string Vote { get; set; } = string.Empty;
        public string? ConditionsText { get; set; }
        public string? Rationale { get; set; }
        public DateTimeOffset VotedAt { get; set; }
    }

    public class CastCommitteeVoteInput
    {
        public Guid AssessmentId { get; set; }
        public Guid CommitteeMemberUserId { get; set; }
        public string Vote { get; set; } = string.Empty;

        /// <summary>Required when Vote = ApproveWithConditions (US-8.2 AC2) - enforced by the
        /// committee_vote table's own CHECK constraint, not re-validated here.</summary>
        public string? ConditionsText { get; set; }

        /// <summary>Required when Vote = Reject or Defer (US-8.2 AC3/AC4) - same, DB-enforced.</summary>
        public string? Rationale { get; set; }
    }

    /// <summary>US-8.3 - the resolved outcome. See docs/architecture/architecture-mapping.md for
    /// the resolution rule CommitteeService applies.</summary>
    public class CommitteeDecision
    {
        public Guid Id { get; set; }

        /// <summary>Approved | Rejected | Deferred | ApprovedWithConditions.</summary>
        public string Resolution { get; set; } = string.Empty;
        public string? ConditionsText { get; set; }
        public DateTimeOffset DecidedAt { get; set; }
    }
}
