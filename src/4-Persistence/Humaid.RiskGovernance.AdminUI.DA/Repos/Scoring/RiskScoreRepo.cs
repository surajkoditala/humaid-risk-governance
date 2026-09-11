namespace Humaid.RiskGovernance.AdminUI.DA.Repos.Scoring
{
    using System.Text.Json;
    using Dapper;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Scoring;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Scoring;

    public class RiskScoreRepo : IRiskScoreRepo
    {
        private readonly DapperConnectionFactory _connectionFactory;

        public RiskScoreRepo(DapperConnectionFactory connectionFactory)
        {
            _connectionFactory = connectionFactory;
        }

        public async Task<Guid> UpsertConfigAsync(UpsertScoringConfigInput input)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            return await conn.QuerySingleAsync<Guid>(
                "SELECT func_upsertScoringConfig(@RiskCategoryId, @MaxMitigationFactor, @Reason, @ActorUserId)",
                input);
        }

        public async Task<(Guid Id, decimal ResidualRating, decimal MitigationFactorApplied)> CalculateAndSaveAsync(CalculateRiskScoreInput input)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            var row = await conn.QuerySingleAsync<CalculateResultRow>(
                @"SELECT * FROM func_calculateAndSaveRiskScore(
                    @AssessmentId, @RiskCategoryId, @InherentRating, @ControlIdsCreditedJson::jsonb, @ControlEffectiveness)",
                new
                {
                    input.AssessmentId,
                    input.RiskCategoryId,
                    input.InherentRating,
                    ControlIdsCreditedJson = JsonSerializer.Serialize(input.ControlIdsCredited),
                    input.ControlEffectiveness,
                });
            return (row.Id, row.ResidualRating, row.MitigationFactorApplied);
        }

        public async Task<Guid> OverrideAsync(OverrideRiskScoreInput input)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            return await conn.QuerySingleAsync<Guid>(
                "SELECT func_overrideRiskScore(@AssessmentId, @RiskCategoryId, @NewResidualRating, @Reason, @ActorUserId)",
                input);
        }

        public async Task<IReadOnlyList<RiskScore>> GetScoresAsync(Guid assessmentId)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            var rows = await conn.QueryAsync<RiskScore>(
                "SELECT * FROM func_getRiskScores(@assessmentId)", new { assessmentId });
            return rows.AsList();
        }

        public async Task<IReadOnlyList<Control>> GetControlsAsync(Guid riskCategoryId)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            var rows = await conn.QueryAsync<Control>(
                "SELECT * FROM func_getControls(@riskCategoryId)", new { riskCategoryId });
            return rows.AsList();
        }

        private class CalculateResultRow
        {
            public Guid Id { get; set; }
            public decimal ResidualRating { get; set; }
            public decimal MitigationFactorApplied { get; set; }
        }
    }
}
