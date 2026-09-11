namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Committee
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Committee;

    public interface ICommitteeService
    {
        /// <summary>US-8.1: assessment must already be Finalized.</summary>
        Task RouteToCommitteeAsync(Guid assessmentId, Guid actorUserId);
        Task<IReadOnlyList<CommitteeQueueItem>> GetQueueAsync();

        /// <summary>US-8.2. After casting, automatically resolves the decision once the configured
        /// quorum (workflow_rule "CommitteeQuorum") is met - see
        /// docs/architecture/architecture-mapping.md for the resolution rule.</summary>
        Task<Guid> CastVoteAsync(CastCommitteeVoteInput input);
        Task<IReadOnlyList<CommitteeVote>> GetVotesAsync(Guid assessmentId);
        Task<CommitteeDecision?> GetDecisionAsync(Guid assessmentId);
    }
}
