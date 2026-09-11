namespace Humaid.RiskGovernance.AdminUI.DA.Repos.Assessment
{
    using Dapper;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Assessment;

    public class AssessmentRepo : IAssessmentRepo
    {
        private readonly DapperConnectionFactory _connectionFactory;

        public AssessmentRepo(DapperConnectionFactory connectionFactory)
        {
            _connectionFactory = connectionFactory;
        }

        public async Task<Guid> GetOrCreateAsync(Guid changeRequestId)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            return await conn.QuerySingleAsync<Guid>(
                "SELECT func_getOrCreateAssessment(@changeRequestId)", new { changeRequestId });
        }

        public async Task FinalizeAsync(Guid assessmentId, Guid actorUserId)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            await conn.ExecuteAsync(
                "SELECT func_finalizeAssessment(@assessmentId, @actorUserId)", new { assessmentId, actorUserId });
        }

        public async Task<Infrastructure.Models.Assessment.Assessment?> GetByChangeRequestAsync(Guid changeRequestId)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            return await conn.QuerySingleOrDefaultAsync<Infrastructure.Models.Assessment.Assessment>(
                "SELECT * FROM func_getAssessmentByChangeRequest(@changeRequestId)", new { changeRequestId });
        }

        public async Task<Infrastructure.Models.Assessment.Assessment?> GetByIdAsync(Guid assessmentId)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            return await conn.QuerySingleOrDefaultAsync<Infrastructure.Models.Assessment.Assessment>(
                "SELECT * FROM func_getAssessmentById(@assessmentId)", new { assessmentId });
        }
    }
}
