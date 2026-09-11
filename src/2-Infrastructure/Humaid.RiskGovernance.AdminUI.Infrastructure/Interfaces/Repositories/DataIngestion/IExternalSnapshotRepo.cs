namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.DataIngestion
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.DataIngestion;

    public interface IExternalSnapshotRepo
    {
        Task SaveAsync(Guid changeRequestId, Guid? mockCustomerId, string? customerRiskContextJson, Guid? mockProductId, string? productRiskContextJson, Guid? mockVendorId, string? vendorRiskContextJson);
        Task<ExternalSnapshot?> GetByChangeRequestIdAsync(Guid changeRequestId);
    }
}
