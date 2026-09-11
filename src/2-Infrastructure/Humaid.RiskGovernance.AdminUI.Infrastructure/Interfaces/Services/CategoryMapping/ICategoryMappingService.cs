namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.CategoryMapping
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.CategoryMapping;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.RiskFramework;

    public interface ICategoryMappingService
    {
        Task<IReadOnlyList<RiskCategory>> GetAllRiskCategoriesAsync();
        /// <summary>US-2.1: fetches the change request, calls <c>ICategoryMappingAiClient</c>, saves
        /// each proposal. Flags explicitly (does not guess) when no framework mapping exists for the
        /// change type (US-2.1 AC3).</summary>
        Task<IReadOnlyList<CategoryMapping>> ProposeAsync(Guid assessmentId, Guid changeRequestId);
        Task<Guid> OverrideAsync(OverrideCategoryMappingInput input);
        Task<IReadOnlyList<CategoryMapping>> GetMappingAsync(Guid assessmentId);
    }
}
