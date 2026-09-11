namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Ai
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Ai;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.RiskFramework;

    /// <summary>
    /// US-2.1: real Claude call. Grounded against <paramref name="defaults"/> (the change-type ->
    /// category lookup) so the model proposes from a fixed, named framework rather than inventing
    /// categories - implemented in <c>Humaid.RiskGovernance.AdminUI.AI</c>.
    /// </summary>
    public interface ICategoryMappingAiClient
    {
        Task<IReadOnlyList<CategoryMappingProposal>> ProposeAsync(
            string changeType,
            string title,
            string description,
            IReadOnlyList<ChangeTypeCategoryDefault> defaults,
            string? externalContextSummary = null,
            CancellationToken cancellationToken = default);
    }
}
