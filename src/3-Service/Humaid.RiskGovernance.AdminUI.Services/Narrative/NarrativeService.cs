namespace Humaid.RiskGovernance.AdminUI.Services.Narrative
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Ai;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Assessment;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.CategoryMapping;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.ChangeRequests;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.DocumentExtraction;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Narrative;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.PolicyResearch;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Narrative;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Ai;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Narrative;
    using System.Text.Json;

    /// <summary>US-5.1/US-5.2. Gathers the mapped category, relied-upon policy, and extracted
    /// facts an assessment already has, sends them to <see cref="INarrativeDraftingAiClient"/>,
    /// and persists the result as a fresh 'AiDrafted' section - never as a fabricated fact.</summary>
    public class NarrativeService : INarrativeService
    {
        private readonly INarrativeSectionRepo _narrativeSectionRepo;
        private readonly IAssessmentRepo _assessmentRepo;
        private readonly IChangeRequestRepo _changeRequestRepo;
        private readonly ICategoryMappingRepo _categoryMappingRepo;
        private readonly IPolicyResearchRepo _policyResearchRepo;
        private readonly IExtractedFieldRepo _extractedFieldRepo;
        private readonly INarrativeDraftingAiClient _aiClient;

        public NarrativeService(
            INarrativeSectionRepo narrativeSectionRepo,
            IAssessmentRepo assessmentRepo,
            IChangeRequestRepo changeRequestRepo,
            ICategoryMappingRepo categoryMappingRepo,
            IPolicyResearchRepo policyResearchRepo,
            IExtractedFieldRepo extractedFieldRepo,
            INarrativeDraftingAiClient aiClient)
        {
            _narrativeSectionRepo = narrativeSectionRepo;
            _assessmentRepo = assessmentRepo;
            _changeRequestRepo = changeRequestRepo;
            _categoryMappingRepo = categoryMappingRepo;
            _policyResearchRepo = policyResearchRepo;
            _extractedFieldRepo = extractedFieldRepo;
            _aiClient = aiClient;
        }

        public async Task<NarrativeSection> DraftAsync(Guid assessmentId, Guid riskCategoryId, string? regenerationFeedback = null)
        {
            var assessment = await _assessmentRepo.GetByIdAsync(assessmentId)
                ?? throw new InvalidOperationException($"Assessment {assessmentId} not found.");
            var changeRequest = await _changeRequestRepo.GetByIdAsync(assessment.ChangeRequestId)
                ?? throw new InvalidOperationException($"Change request {assessment.ChangeRequestId} not found.");

            var mapping = await _categoryMappingRepo.GetMappingAsync(assessmentId);
            var category = mapping.FirstOrDefault(m => m.RiskCategoryId == riskCategoryId && m.IsActive)
                ?? throw new InvalidOperationException($"Risk category {riskCategoryId} is not an active mapped category for this assessment.");

            var reliance = await _policyResearchRepo.GetRelianceAsync(assessmentId);
            var reliedUponExcerpts = reliance
                .Where(r => r.Decision == "ReliedUpon" && (r.RiskCategoryId == null || r.RiskCategoryId == riskCategoryId))
                .Select(r => $"[{r.SectionRef}] {r.ChunkText}")
                .ToList();

            var extractedFields = await _extractedFieldRepo.GetFieldsAsync(changeRequest.Id);
            var extractedFacts = extractedFields
                .Where(f => !string.IsNullOrWhiteSpace(f.FieldValue))
                .Select(f => $"{f.FieldKey}: {f.FieldValue}")
                .ToList();

            var draft = await _aiClient.DraftAsync(new NarrativeDraftInput
            {
                ChangeType = changeRequest.ChangeType,
                ChangeTitle = changeRequest.Title,
                ChangeDescription = changeRequest.Description,
                RiskCategoryId = riskCategoryId,
                CategoryName = category.CategoryName,
                CategoryCitation = category.CitationSection,
                ReliedUponPolicyExcerpts = reliedUponExcerpts,
                ExtractedFieldFacts = extractedFacts,
                RegenerationFeedback = regenerationFeedback,
            });

            await _narrativeSectionRepo.SaveDraftAsync(
                assessmentId, riskCategoryId, draft.NarrativeText, JsonSerializer.Serialize(draft.UnsupportedClaims));

            var sections = await _narrativeSectionRepo.GetSectionsAsync(assessmentId);
            return sections.First(s => s.RiskCategoryId == riskCategoryId);
        }

        public Task<Guid> ReviewAsync(Guid assessmentId, Guid riskCategoryId, Guid actorUserId) =>
            _narrativeSectionRepo.ReviewAsync(assessmentId, riskCategoryId, actorUserId);

        public Task<Guid> EditAsync(EditNarrativeSectionInput input) => _narrativeSectionRepo.EditAsync(input);

        public Task<IReadOnlyList<NarrativeSection>> GetSectionsAsync(Guid assessmentId) =>
            _narrativeSectionRepo.GetSectionsAsync(assessmentId);
    }
}
