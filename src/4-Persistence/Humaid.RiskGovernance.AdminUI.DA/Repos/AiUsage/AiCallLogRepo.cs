namespace Humaid.RiskGovernance.AdminUI.DA.Repos.AiUsage
{
    using Dapper;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.AiUsage;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.AiUsage;

    public class AiCallLogRepo : IAiCallLogRepo
    {
        private readonly DapperConnectionFactory _connectionFactory;

        public AiCallLogRepo(DapperConnectionFactory connectionFactory)
        {
            _connectionFactory = connectionFactory;
        }

        public async Task<Guid> LogAsync(LogAiCallInput input)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            return await conn.QuerySingleAsync<Guid>(
                @"SELECT func_logAiCall(
                    @ChangeRequestId, @AssessmentId, @Operation, @Provider, @Model,
                    @InputTokens, @OutputTokens, @CacheReadTokens, @CacheCreationTokens, @DurationMs)",
                input);
        }

        public async Task<IReadOnlyList<AiCall>> GetForRequestAsync(Guid changeRequestId)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            var rows = await conn.QueryAsync<AiCall>(
                "SELECT * FROM func_getAiCallsForRequest(@changeRequestId)", new { changeRequestId });
            return rows.AsList();
        }
    }
}
