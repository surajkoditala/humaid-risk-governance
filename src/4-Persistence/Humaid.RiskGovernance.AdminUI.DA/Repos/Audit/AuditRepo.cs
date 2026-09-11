namespace Humaid.RiskGovernance.AdminUI.DA.Repos.Audit
{
    using Dapper;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Audit;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Audit;

    public class AuditRepo : IAuditRepo
    {
        private readonly DapperConnectionFactory _connectionFactory;

        public AuditRepo(DapperConnectionFactory connectionFactory)
        {
            _connectionFactory = connectionFactory;
        }

        public async Task<Guid> AppendAsync(AppendAuditEventInput input)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            return await conn.QuerySingleAsync<Guid>(
                @"SELECT func_appendAuditEvent(
                    @ChangeRequestId, @AssessmentId, @EntityType, @EntityId, @Action,
                    @ActorUserId, @ActorLabel, @BeforeValueJson::jsonb, @AfterValueJson::jsonb, @Reason)",
                input);
        }

        public async Task<IReadOnlyList<AuditEvent>> GetTrailForRequestAsync(Guid changeRequestId)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            var rows = await conn.QueryAsync<AuditEvent>(
                "SELECT * FROM func_getAuditTrailForRequest(@changeRequestId)", new { changeRequestId });
            return rows.AsList();
        }
    }
}
