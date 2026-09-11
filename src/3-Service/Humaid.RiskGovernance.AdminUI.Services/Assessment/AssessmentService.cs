namespace Humaid.RiskGovernance.AdminUI.Services.Assessment
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Assessment;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.CategoryMapping;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Narrative;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.PolicyResearch;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Assessment;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Assessment;

    /// <summary>US-6.3: finalization is blocked (with a specific, listed reason) until every
    /// mapped category has both a reviewed/edited narrative and at least one policy reliance
    /// decision - never a silent pass-through.</summary>
    public class AssessmentService : IAssessmentService
    {
        private readonly IAssessmentRepo _assessmentRepo;
        private readonly ICategoryMappingRepo _categoryMappingRepo;
        private readonly INarrativeSectionRepo _narrativeSectionRepo;
        private readonly IPolicyResearchRepo _policyResearchRepo;

        public AssessmentService(
            IAssessmentRepo assessmentRepo,
            ICategoryMappingRepo categoryMappingRepo,
            INarrativeSectionRepo narrativeSectionRepo,
            IPolicyResearchRepo policyResearchRepo)
        {
            _assessmentRepo = assessmentRepo;
            _categoryMappingRepo = categoryMappingRepo;
            _narrativeSectionRepo = narrativeSectionRepo;
            _policyResearchRepo = policyResearchRepo;
        }

        public Task<Guid> OpenWorkspaceAsync(Guid changeRequestId) => _assessmentRepo.GetOrCreateAsync(changeRequestId);

        public Task<Assessment?> GetByChangeRequestAsync(Guid changeRequestId) => _assessmentRepo.GetByChangeRequestAsync(changeRequestId);

        public async Task<AssessmentReadiness> CheckReadinessAsync(Guid assessmentId)
        {
            var readiness = new AssessmentReadiness();

            var activeCategories = (await _categoryMappingRepo.GetMappingAsync(assessmentId))
                .Where(m => m.IsActive)
                .ToList();

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

            return readiness;
        }

        public async Task FinalizeAsync(Guid assessmentId, Guid actorUserId)
        {
            var readiness = await CheckReadinessAsync(assessmentId);
            if (!readiness.IsReady)
            {
                var outstanding = new List<string>();
                if (readiness.OutstandingNarrativeSections.Count > 0)
                    outstanding.Add($"Narrative not yet reviewed for: {string.Join(", ", readiness.OutstandingNarrativeSections)}");
                if (readiness.CategoriesMissingPolicyReliance.Count > 0)
                    outstanding.Add($"No policy reviewed for: {string.Join(", ", readiness.CategoriesMissingPolicyReliance)}");
                throw new InvalidOperationException(string.Join(" ", outstanding));
            }
            await _assessmentRepo.FinalizeAsync(assessmentId, actorUserId);
        }
    }
}
