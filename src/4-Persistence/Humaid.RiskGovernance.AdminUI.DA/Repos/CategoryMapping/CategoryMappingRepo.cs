namespace Humaid.RiskGovernance.AdminUI.DA.Repos.CategoryMapping
{
    using Dapper;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.CategoryMapping;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.CategoryMapping;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.RiskFramework;

    public class CategoryMappingRepo : ICategoryMappingRepo
    {
        private readonly DapperConnectionFactory _connectionFactory;

        public CategoryMappingRepo(DapperConnectionFactory connectionFactory)
        {
            _connectionFactory = connectionFactory;
        }

        public async Task<IReadOnlyList<ChangeTypeCategoryDefault>> GetChangeTypeDefaultsAsync(string changeType)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            var rows = await conn.QueryAsync<ChangeTypeCategoryDefault>(
                "SELECT * FROM func_getChangeTypeCategoryDefaults(@changeType)", new { changeType });
            return rows.AsList();
        }

        public async Task<IReadOnlyList<RiskCategory>> GetAllRiskCategoriesAsync()
        {
            await using var conn = await _connectionFactory.OpenAsync();
            var rows = await conn.QueryAsync<RiskCategory>("SELECT * FROM func_getAllRiskCategories()");
            return rows.AsList();
        }

        public async Task<Guid> SaveProposalAsync(Guid assessmentId, Guid riskCategoryId, string citation)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            return await conn.QuerySingleAsync<Guid>(
                "SELECT func_saveCategoryMappingProposal(@assessmentId, @riskCategoryId, @citation)",
                new { assessmentId, riskCategoryId, citation });
        }

        public async Task<Guid> OverrideAsync(OverrideCategoryMappingInput input)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            return await conn.QuerySingleAsync<Guid>(
                "SELECT func_overrideCategoryMapping(@AssessmentId, @RiskCategoryId, @IsActive, @Reason, @ActorUserId)",
                input);
        }

        public async Task<IReadOnlyList<CategoryMapping>> GetMappingAsync(Guid assessmentId)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            var rows = await conn.QueryAsync<CategoryMapping>(
                "SELECT * FROM func_getCategoryMapping(@assessmentId)", new { assessmentId });
            return rows.AsList();
        }
    }
}
