namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.DataIngestion
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.DataIngestion;

    public interface IDataIngestionService
    {
        /// <summary>
        /// Fetches whichever of customer/product/vendor was linked at Intake from Mock Systems and
        /// persists an immutable snapshot against the change request. Best-effort: Mock Systems
        /// being unreachable does not fail intake - see DataIngestionService for the reasoning.
        /// A no-op when all three ids are null (change types with no obvious linked entity).
        /// </summary>
        Task IngestAsync(Guid changeRequestId, Guid? mockCustomerId, Guid? mockProductId, Guid? mockVendorId, CancellationToken cancellationToken = default);

        Task<ExternalSnapshot?> GetSnapshotAsync(Guid changeRequestId, CancellationToken cancellationToken = default);
    }
}
