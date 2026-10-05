namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Scoring
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Scoring;

    public interface IScoringService
    {
        Task<Guid> UpsertConfigAsync(UpsertScoringConfigInput input);

        /// <summary>US-7.1: deterministic formula, no LLM. Re-validates residual > 0 in C# as
        /// defense in depth on top of the DB CHECK constraints.</summary>
        Task<RiskScore> CalculateAsync(CalculateRiskScoreInput input);

        /// <summary>US-7.2: reason mandatory; rejects any value <![CDATA[<=]]> 0.</summary>
        Task<Guid> OverrideAsync(OverrideRiskScoreInput input);
        Task<IReadOnlyList<RiskScore>> GetScoresAsync(Guid assessmentId);
        Task<IReadOnlyList<Control>> GetControlsAsync(Guid riskCategoryId);
    }
}
