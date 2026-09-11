namespace Humaid.RiskGovernance.AdminUI.DA.Repos.Committee
{
    using Dapper;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Committee;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Committee;

    public class CommitteeRepo : ICommitteeRepo
    {
        private readonly DapperConnectionFactory _connectionFactory;

        public CommitteeRepo(DapperConnectionFactory connectionFactory)
        {
            _connectionFactory = connectionFactory;
        }

        public async Task RouteAsync(Guid assessmentId, Guid actorUserId)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            await conn.ExecuteAsync("SELECT func_routeToCommittee(@assessmentId, @actorUserId)", new { assessmentId, actorUserId });
        }

        public async Task<IReadOnlyList<CommitteeQueueItem>> GetQueueAsync()
        {
            await using var conn = await _connectionFactory.OpenAsync();
            var rows = await conn.QueryAsync<CommitteeQueueItem>("SELECT * FROM func_getCommitteeQueue()");
            return rows.AsList();
        }

        public async Task<Guid> CastVoteAsync(CastCommitteeVoteInput input)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            return await conn.QuerySingleAsync<Guid>(
                "SELECT func_castCommitteeVote(@AssessmentId, @CommitteeMemberUserId, @Vote, @ConditionsText, @Rationale)",
                input);
        }

        public async Task<IReadOnlyList<CommitteeVote>> GetVotesAsync(Guid assessmentId)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            var rows = await conn.QueryAsync<CommitteeVote>("SELECT * FROM func_getCommitteeVotes(@assessmentId)", new { assessmentId });
            return rows.AsList();
        }

        public async Task<Guid> RecordDecisionAsync(Guid assessmentId, string resolution, string? conditionsText)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            return await conn.QuerySingleAsync<Guid>(
                "SELECT func_recordCommitteeDecision(@assessmentId, @resolution, @conditionsText)",
                new { assessmentId, resolution, conditionsText });
        }

        public async Task<CommitteeDecision?> GetDecisionAsync(Guid assessmentId)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            return await conn.QuerySingleOrDefaultAsync<CommitteeDecision>(
                "SELECT * FROM func_getCommitteeDecision(@assessmentId)", new { assessmentId });
        }
    }
}
