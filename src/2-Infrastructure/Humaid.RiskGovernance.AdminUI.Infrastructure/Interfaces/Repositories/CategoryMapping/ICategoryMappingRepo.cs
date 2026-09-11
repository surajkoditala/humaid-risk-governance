namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.CategoryMapping
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.CategoryMapping;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.RiskFramework;

    public interface ICategoryMappingRepo
    {
        Task<IReadOnlyList<ChangeTypeCategoryDefault>> GetChangeTypeDefaultsAsync(string changeType);
        Task<IReadOnlyList<RiskCategory>> GetAllRiskCategoriesAsync();
        Task<Guid> SaveProposalAsync(Guid assessmentId, Guid riskCategoryId, string citation);
        Task<Guid> OverrideAsync(OverrideCategoryMappingInput input);
        Task<IReadOnlyList<CategoryMapping>> GetMappingAsync(Guid assessmentId);
    }
}
