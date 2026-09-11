namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Scoring
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Scoring;

    public interface IRiskScoreRepo
    {
        Task<Guid> UpsertConfigAsync(UpsertScoringConfigInput input);
        Task<(Guid Id, decimal ResidualRating, decimal MitigationFactorApplied)> CalculateAndSaveAsync(CalculateRiskScoreInput input);
        Task<Guid> OverrideAsync(OverrideRiskScoreInput input);
        Task<IReadOnlyList<RiskScore>> GetScoresAsync(Guid assessmentId);
        Task<IReadOnlyList<Control>> GetControlsAsync(Guid riskCategoryId);
    }
}
