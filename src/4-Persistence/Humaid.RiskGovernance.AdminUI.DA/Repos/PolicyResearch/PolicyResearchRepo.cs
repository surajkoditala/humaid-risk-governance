namespace Humaid.RiskGovernance.AdminUI.DA.Repos.PolicyResearch
{
    using Dapper;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.PolicyResearch;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.PolicyResearch;

    public class PolicyResearchRepo : IPolicyResearchRepo
    {
        private readonly DapperConnectionFactory _connectionFactory;

        public PolicyResearchRepo(DapperConnectionFactory connectionFactory)
        {
            _connectionFactory = connectionFactory;
        }

        public async Task<IReadOnlyList<PolicyChunkSearchResult>> SearchChunksAsync(string queryText, Guid? riskCategoryId, int topK)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            var rows = await conn.QueryAsync<PolicyChunkSearchResult>(
                "SELECT * FROM func_searchPolicyChunks(@queryText, @riskCategoryId, @topK)",
                new { queryText, riskCategoryId, topK });
            return rows.AsList();
        }

        public async Task<Guid> RecordRelianceAsync(RecordPolicyRelianceInput input)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            return await conn.QuerySingleAsync<Guid>(
                "SELECT func_recordPolicyReliance(@AssessmentId, @RiskCategoryId, @PolicyChunkId, @Decision, @DecidedByUserId)",
                input);
        }

        public async Task<IReadOnlyList<PolicyReliance>> GetRelianceAsync(Guid assessmentId)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            var rows = await conn.QueryAsync<PolicyReliance>(
                "SELECT * FROM func_getPolicyReliance(@assessmentId)", new { assessmentId });
            return rows.AsList();
        }
    }
}
