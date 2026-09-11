namespace Humaid.RiskGovernance.AdminUI.DA.Repos.Narrative
{
    using Dapper;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Narrative;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Narrative;

    public class NarrativeSectionRepo : INarrativeSectionRepo
    {
        private readonly DapperConnectionFactory _connectionFactory;

        public NarrativeSectionRepo(DapperConnectionFactory connectionFactory)
        {
            _connectionFactory = connectionFactory;
        }

        public async Task<Guid> SaveDraftAsync(Guid assessmentId, Guid riskCategoryId, string narrativeText, string unsupportedClaimFlagsJson)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            return await conn.QuerySingleAsync<Guid>(
                "SELECT func_saveNarrativeSection(@assessmentId, @riskCategoryId, @narrativeText, @unsupportedClaimFlagsJson::jsonb)",
                new { assessmentId, riskCategoryId, narrativeText, unsupportedClaimFlagsJson });
        }

        public async Task<Guid> ReviewAsync(Guid assessmentId, Guid riskCategoryId, Guid actorUserId)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            return await conn.QuerySingleAsync<Guid>(
                "SELECT func_reviewNarrativeSection(@assessmentId, @riskCategoryId, @actorUserId)",
                new { assessmentId, riskCategoryId, actorUserId });
        }

        public async Task<Guid> EditAsync(EditNarrativeSectionInput input)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            return await conn.QuerySingleAsync<Guid>(
                "SELECT func_editNarrativeSection(@AssessmentId, @RiskCategoryId, @NewText, @Reason, @ActorUserId)",
                input);
        }

        public async Task<IReadOnlyList<NarrativeSection>> GetSectionsAsync(Guid assessmentId)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            var rows = await conn.QueryAsync<NarrativeSection>(
                "SELECT * FROM func_getNarrativeSections(@assessmentId)", new { assessmentId });
            return rows.AsList();
        }
    }
}
