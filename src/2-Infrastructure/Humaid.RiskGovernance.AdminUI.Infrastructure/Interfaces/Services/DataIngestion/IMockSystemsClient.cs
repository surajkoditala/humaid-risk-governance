namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.DataIngestion
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.DataIngestion;

    /// <summary>
    /// HTTP client for Humaid.RiskGovernance.MockSystems (src/6-MockExternalSystems) - the ONLY
    /// thing in the Workbench allowed to call it. Everything downstream (AI clients, scoring,
    /// analyst UI) reads the immutable snapshot <see cref="IDataIngestionService"/> produces from
    /// these calls, never this client directly - see
    /// docs/architecture/architecture-mapping.md's "Mock External Systems" section.
    /// </summary>
    public interface IMockSystemsClient
    {
        Task<IReadOnlyList<MockLookupOption>> ListCustomersAsync(CancellationToken cancellationToken = default);
        Task<IReadOnlyList<MockLookupOption>> ListProductsAsync(CancellationToken cancellationToken = default);
        Task<IReadOnlyList<MockLookupOption>> ListVendorsAsync(CancellationToken cancellationToken = default);

        Task<MockCustomerContext?> GetCustomerAsync(Guid id, CancellationToken cancellationToken = default);
        Task<MockProductContext?> GetProductAsync(Guid id, CancellationToken cancellationToken = default);
        Task<MockVendorContext?> GetVendorAsync(Guid id, CancellationToken cancellationToken = default);

        /// <summary>Feedback loop, inbound side - see CommitteeService.TryResolveDecisionAsync.</summary>
        Task PushCustomerRiskFlagAsync(Guid id, string riskFlag, CancellationToken cancellationToken = default);
        Task PushProductRiskFlagAsync(Guid id, bool goLive, string riskRating, CancellationToken cancellationToken = default);
        Task PushVendorRiskFlagAsync(Guid id, string updatedRiskRating, CancellationToken cancellationToken = default);
    }
}
