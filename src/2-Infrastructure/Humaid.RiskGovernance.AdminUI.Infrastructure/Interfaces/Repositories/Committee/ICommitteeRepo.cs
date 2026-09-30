namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Committee
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Committee;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core;

    public interface ICommitteeRepo
    {
        Task RouteAsync(Guid assessmentId, Guid actorUserId);
        Task<PagedResult<CommitteeQueueItem>> GetQueueAsync(GridQuery query);
        Task<Guid> CastVoteAsync(CastCommitteeVoteInput input);
        Task<IReadOnlyList<CommitteeVote>> GetVotesAsync(Guid assessmentId);
        Task<Guid> RecordDecisionAsync(Guid assessmentId, string resolution, string? conditionsText);
        Task<CommitteeDecision?> GetDecisionAsync(Guid assessmentId);
    }
}
