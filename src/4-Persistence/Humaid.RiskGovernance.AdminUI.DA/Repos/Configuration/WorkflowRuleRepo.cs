namespace Humaid.RiskGovernance.AdminUI.DA.Repos.Configuration
{
    using Dapper;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Configuration;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Configuration;

    public class WorkflowRuleRepo : IWorkflowRuleRepo
    {
        private readonly DapperConnectionFactory _connectionFactory;

        public WorkflowRuleRepo(DapperConnectionFactory connectionFactory)
        {
            _connectionFactory = connectionFactory;
        }

        public async Task<WorkflowRule?> GetActiveAsync(string ruleKey)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            return await conn.QuerySingleOrDefaultAsync<WorkflowRule>(
                "SELECT * FROM func_getWorkflowRule(@ruleKey)", new { ruleKey });
        }

        public async Task<IReadOnlyList<WorkflowRule>> GetAllActiveAsync()
        {
            await using var conn = await _connectionFactory.OpenAsync();
            var rows = await conn.QueryAsync<WorkflowRule>("SELECT * FROM func_getAllActiveWorkflowRules()");
            return rows.AsList();
        }

        public async Task<Guid> UpsertAsync(UpsertWorkflowRuleInput input)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            return await conn.QuerySingleAsync<Guid>(
                "SELECT func_upsertWorkflowRule(@RuleKey, @RuleValueJson::jsonb, @Reason, @ActorUserId)", input);
        }
    }
}
