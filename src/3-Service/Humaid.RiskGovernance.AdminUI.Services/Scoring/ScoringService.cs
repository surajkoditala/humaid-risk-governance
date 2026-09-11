namespace Humaid.RiskGovernance.AdminUI.Services.Scoring
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Scoring;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Scoring;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Scoring;

    /// <summary>US-7.1/US-7.2. Deterministic - no LLM anywhere in this class.</summary>
    public class ScoringService : IScoringService
    {
        private readonly IRiskScoreRepo _riskScoreRepo;

        public ScoringService(IRiskScoreRepo riskScoreRepo)
        {
            _riskScoreRepo = riskScoreRepo;
        }

        public Task<Guid> UpsertConfigAsync(UpsertScoringConfigInput input)
        {
            // US-10.1 AC2: reject in C# too - defense in depth on top of the DB CHECK + RAISE.
            if (input.MaxMitigationFactor < 0 || input.MaxMitigationFactor >= 1.0m)
            {
                throw new InvalidOperationException(
                    "max_mitigation_factor must be in [0, 1.0) - a value of 1.0 or more would let residual risk reach zero.");
            }
            return _riskScoreRepo.UpsertConfigAsync(input);
        }

        public async Task<RiskScore> CalculateAsync(CalculateRiskScoreInput input)
        {
            var (id, residual, _) = await _riskScoreRepo.CalculateAndSaveAsync(input);

            // Re-validate the DB's own mathematical guarantee here too (schema/010_scoring.sql).
            if (residual <= 0)
            {
                throw new InvalidOperationException(
                    "Calculated residual risk was not greater than zero - this should be mathematically impossible; check scoring_config.");
            }

            var scores = await _riskScoreRepo.GetScoresAsync(input.AssessmentId);
            return scores.First(s => s.Id == id);
        }

        public Task<Guid> OverrideAsync(OverrideRiskScoreInput input)
        {
            if (input.NewResidualRating <= 0)
            {
                throw new InvalidOperationException(
                    "residual_rating must be greater than zero - controls mitigate risk, they never eliminate it.");
            }
            if (string.IsNullOrWhiteSpace(input.Reason))
            {
                throw new InvalidOperationException("A reason is required to override a risk score.");
            }
            return _riskScoreRepo.OverrideAsync(input);
        }

        public Task<IReadOnlyList<RiskScore>> GetScoresAsync(Guid assessmentId) => _riskScoreRepo.GetScoresAsync(assessmentId);

        public Task<IReadOnlyList<Control>> GetControlsAsync(Guid riskCategoryId) => _riskScoreRepo.GetControlsAsync(riskCategoryId);
    }
}
