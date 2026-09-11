namespace Humaid.RiskGovernance.AdminUI.Services.CategoryMapping
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Ai;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.CategoryMapping;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.ChangeRequests;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.CategoryMapping;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.DataIngestion;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.CategoryMapping;

    public class CategoryMappingService : ICategoryMappingService
    {
        private readonly ICategoryMappingRepo _categoryMappingRepo;
        private readonly IChangeRequestRepo _changeRequestRepo;
        private readonly ICategoryMappingAiClient _aiClient;
        private readonly IDataIngestionService _dataIngestionService;

        public CategoryMappingService(
            ICategoryMappingRepo categoryMappingRepo,
            IChangeRequestRepo changeRequestRepo,
            ICategoryMappingAiClient aiClient,
            IDataIngestionService dataIngestionService)
        {
            _categoryMappingRepo = categoryMappingRepo;
            _changeRequestRepo = changeRequestRepo;
            _aiClient = aiClient;
            _dataIngestionService = dataIngestionService;
        }

        public async Task<IReadOnlyList<CategoryMapping>> ProposeAsync(Guid assessmentId, Guid changeRequestId)
        {
            var changeRequest = await _changeRequestRepo.GetByIdAsync(changeRequestId)
                ?? throw new InvalidOperationException($"Change request {changeRequestId} not found.");

            var defaults = await _categoryMappingRepo.GetChangeTypeDefaultsAsync(changeRequest.ChangeType);
            var externalContextSummary = await BuildExternalContextSummaryAsync(changeRequestId);
            var proposals = await _aiClient.ProposeAsync(
                changeRequest.ChangeType, changeRequest.Title, changeRequest.Description, defaults, externalContextSummary);

            foreach (var proposal in proposals)
            {
                await _categoryMappingRepo.SaveProposalAsync(assessmentId, proposal.RiskCategoryId, proposal.Citation);
            }

            return await _categoryMappingRepo.GetMappingAsync(assessmentId);
        }

        public Task<Guid> OverrideAsync(OverrideCategoryMappingInput input) => _categoryMappingRepo.OverrideAsync(input);

        public Task<IReadOnlyList<CategoryMapping>> GetMappingAsync(Guid assessmentId) => _categoryMappingRepo.GetMappingAsync(assessmentId);

        public Task<IReadOnlyList<Humaid.RiskGovernance.AdminUI.Infrastructure.Models.RiskFramework.RiskCategory>> GetAllRiskCategoriesAsync() =>
            _categoryMappingRepo.GetAllRiskCategoriesAsync();

        /// <summary>
        /// A short, human-readable summary of whatever Mock Systems context Data Ingestion
        /// captured at intake (Phase 3) - or null if no snapshot exists (no linked entity, or
        /// Mock Systems was unreachable at intake time). The AI client treats this as extra
        /// grounding only, never as a category or citation source in its own right.
        /// </summary>
        private async Task<string?> BuildExternalContextSummaryAsync(Guid changeRequestId)
        {
            var snapshot = await _dataIngestionService.GetSnapshotAsync(changeRequestId);
            if (snapshot is null) return null;

            var parts = new List<string>();
            if (snapshot.CustomerRiskContextJson is not null) parts.Add($"Customer risk context: {snapshot.CustomerRiskContextJson}");
            if (snapshot.ProductRiskContextJson is not null) parts.Add($"Product risk context: {snapshot.ProductRiskContextJson}");
            if (snapshot.VendorRiskContextJson is not null) parts.Add($"Vendor risk context: {snapshot.VendorRiskContextJson}");

            return parts.Count == 0 ? null : string.Join("\n", parts);
        }
    }
}
