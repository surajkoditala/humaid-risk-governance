namespace Humaid.RiskGovernance.AdminUI.Services.Assessment
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Assessment;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.CategoryMapping;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Narrative;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.PolicyResearch;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Scoring;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Users;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Assessment;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Assessment;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core;

    /// <summary>US-6.3: finalization is blocked (with a specific, listed reason) until every
    /// mapped category has both a reviewed/edited narrative and at least one policy reliance
    /// decision - never a silent pass-through.</summary>
    public class AssessmentService : IAssessmentService
    {
        private readonly IAssessmentRepo _assessmentRepo;
        private readonly ICategoryMappingRepo _categoryMappingRepo;
        private readonly INarrativeSectionRepo _narrativeSectionRepo;
        private readonly IPolicyResearchRepo _policyResearchRepo;
        private readonly IRiskScoreRepo _riskScoreRepo;
        private readonly IUserRepo _userRepo;

        public AssessmentService(
            IAssessmentRepo assessmentRepo,
            ICategoryMappingRepo categoryMappingRepo,
            INarrativeSectionRepo narrativeSectionRepo,
            IPolicyResearchRepo policyResearchRepo,
            IRiskScoreRepo riskScoreRepo,
            IUserRepo userRepo)
        {
            _assessmentRepo = assessmentRepo;
            _categoryMappingRepo = categoryMappingRepo;
            _narrativeSectionRepo = narrativeSectionRepo;
            _policyResearchRepo = policyResearchRepo;
            _riskScoreRepo = riskScoreRepo;
            _userRepo = userRepo;
        }

        public Task<Guid> OpenWorkspaceAsync(Guid changeRequestId) => _assessmentRepo.GetOrCreateAsync(changeRequestId);

        public Task<Assessment?> GetByChangeRequestAsync(Guid changeRequestId) => _assessmentRepo.GetByChangeRequestAsync(changeRequestId);

        public async Task<AssessmentReadiness> CheckReadinessAsync(Guid assessmentId)
        {
            var readiness = new AssessmentReadiness();

            var activeCategories = (await _categoryMappingRepo.GetMappingAsync(assessmentId))
                .Where(m => m.IsActive)
                .ToList();

            // DEF-001: zero mapped categories must never read as "ready" - there is nothing here
            // for a human to have reviewed, which is the opposite of finalization-ready.
            readiness.NoCategoriesMapped = activeCategories.Count == 0;

            var sections = await _narrativeSectionRepo.GetSectionsAsync(assessmentId);
            foreach (var category in activeCategories)
            {
                var section = sections.FirstOrDefault(s => s.RiskCategoryId == category.RiskCategoryId);
                if (section is null || section.Status == "AiDrafted")
                {
                    readiness.OutstandingNarrativeSections.Add(category.CategoryName);
                }
            }

            var reliance = await _policyResearchRepo.GetRelianceAsync(assessmentId);
            foreach (var category in activeCategories)
            {
                var hasReliance = reliance.Any(r => r.RiskCategoryId == null || r.RiskCategoryId == category.RiskCategoryId);
                if (!hasReliance)
                {
                    readiness.CategoriesMissingPolicyReliance.Add(category.CategoryName);
                }
            }

            // DEF-001's suggested fix also called out "category without a score" - readiness never
            // checked scoring at all, so a fully-mapped, fully-reviewed assessment with nothing
            // calculated in Epic 7 would still finalize.
            var scores = await _riskScoreRepo.GetScoresAsync(assessmentId);
            foreach (var category in activeCategories)
            {
                if (!scores.Any(s => s.RiskCategoryId == category.RiskCategoryId))
                {
                    readiness.CategoriesMissingScore.Add(category.CategoryName);
                }
            }

            return readiness;
        }

        public async Task FinalizeAsync(Guid assessmentId, Guid actorUserId)
        {
            // DEF-002: a Product Owner id finalizing an assessment returned 200 (audit even
            // recorded them as the finalizer) - US-6.3 AC3 requires this to be the analyst's own,
            // accountable action.
            if (!await _userRepo.HasRoleAsync(actorUserId, "Analyst") && !await _userRepo.HasRoleAsync(actorUserId, "Admin"))
            {
                throw new ValidationException("Only an FCRM Analyst may finalize an assessment.");
            }

            var readiness = await CheckReadinessAsync(assessmentId);
            if (!readiness.IsReady)
            {
                var outstanding = new List<string>();
                if (readiness.NoCategoriesMapped)
                    outstanding.Add("No risk categories are mapped yet.");
                if (readiness.OutstandingNarrativeSections.Count > 0)
                    outstanding.Add($"Narrative not yet reviewed for: {string.Join(", ", readiness.OutstandingNarrativeSections)}");
                if (readiness.CategoriesMissingPolicyReliance.Count > 0)
                    outstanding.Add($"No policy reviewed for: {string.Join(", ", readiness.CategoriesMissingPolicyReliance)}");
                if (readiness.CategoriesMissingScore.Count > 0)
                    outstanding.Add($"No score calculated for: {string.Join(", ", readiness.CategoriesMissingScore)}");
                throw new ValidationException(string.Join(" ", outstanding));
            }
            await _assessmentRepo.FinalizeAsync(assessmentId, actorUserId);
        }
    }
}
