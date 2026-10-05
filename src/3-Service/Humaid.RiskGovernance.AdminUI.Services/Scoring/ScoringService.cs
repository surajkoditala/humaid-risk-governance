namespace Humaid.RiskGovernance.AdminUI.Services.Scoring
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Assessment;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Scoring;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Users;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Scoring;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Scoring;

    /// <summary>US-7.1/US-7.2. Deterministic - no LLM anywhere in this class.</summary>
    public class ScoringService : IScoringService
    {
        private readonly IRiskScoreRepo _riskScoreRepo;
        private readonly IUserRepo _userRepo;
        private readonly IAssessmentRepo _assessmentRepo;

        public ScoringService(IRiskScoreRepo riskScoreRepo, IUserRepo userRepo, IAssessmentRepo assessmentRepo)
        {
            _riskScoreRepo = riskScoreRepo;
            _userRepo = userRepo;
            _assessmentRepo = assessmentRepo;
        }

        // DEF-007: a Finalized assessment's score must lock - see NarrativeService's identical guard.
        private async Task EnsureNotFinalizedAsync(Guid assessmentId)
        {
            var assessment = await _assessmentRepo.GetByIdAsync(assessmentId)
                ?? throw new ValidationException($"Assessment {assessmentId} not found.");
            if (assessment.Status == "Finalized")
            {
                throw new ValidationException("This assessment is finalized and locked from further edits.");
            }
        }

        public async Task<Guid> UpsertConfigAsync(UpsertScoringConfigInput input)
        {
            // DEF-002: a Product Owner id changing scoring configuration returned 200 - US-10.1 is
            // explicitly "FCRM Analyst (with configuration privileges)", not any authenticated user.
            if (!await _userRepo.HasRoleAsync(input.ActorUserId, "Analyst") && !await _userRepo.HasRoleAsync(input.ActorUserId, "Admin"))
            {
                throw new ValidationException("Only an FCRM Analyst may change scoring configuration.");
            }

            // US-10.1 AC2: reject in C# too - defense in depth on top of the DB CHECK + RAISE.
            if (input.MaxMitigationFactor < 0 || input.MaxMitigationFactor >= 1.0m)
            {
                throw new ValidationException(
                    "max_mitigation_factor must be in [0, 1.0) - a value of 1.0 or more would let residual risk reach zero.");
            }
            return await _riskScoreRepo.UpsertConfigAsync(input);
        }

        public async Task<RiskScore> CalculateAsync(CalculateRiskScoreInput input)
        {
            await EnsureNotFinalizedAsync(input.AssessmentId);
            var (id, residual, _) = await _riskScoreRepo.CalculateAndSaveAsync(input);

            // Re-validate the DB's own mathematical guarantee here too (schema/010_scoring.sql).
            if (residual <= 0)
            {
                throw new ValidationException(
                    "Calculated residual risk was not greater than zero - this should be mathematically impossible; check scoring_config.");
            }

            var scores = await _riskScoreRepo.GetScoresAsync(input.AssessmentId);
            return scores.First(s => s.Id == id);
        }

        public async Task<Guid> OverrideAsync(OverrideRiskScoreInput input)
        {
            if (input.NewResidualRating <= 0)
            {
                throw new ValidationException(
                    "residual_rating must be greater than zero - controls mitigate risk, they never eliminate it.");
            }
            if (string.IsNullOrWhiteSpace(input.Reason))
            {
                throw new ValidationException("A reason is required to override a risk score.");
            }
            await EnsureNotFinalizedAsync(input.AssessmentId);
            return await _riskScoreRepo.OverrideAsync(input);
        }

        public Task<IReadOnlyList<RiskScore>> GetScoresAsync(Guid assessmentId) => _riskScoreRepo.GetScoresAsync(assessmentId);

        public Task<IReadOnlyList<Control>> GetControlsAsync(Guid riskCategoryId) => _riskScoreRepo.GetControlsAsync(riskCategoryId);
    }
}
