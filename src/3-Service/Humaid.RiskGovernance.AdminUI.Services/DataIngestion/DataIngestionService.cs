namespace Humaid.RiskGovernance.AdminUI.Services.DataIngestion
{
    using System.Text.Json;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.DataIngestion;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.DataIngestion;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.DataIngestion;
    using Microsoft.Extensions.Logging;

    public class DataIngestionService : IDataIngestionService
    {
        private readonly IMockSystemsClient _mockSystemsClient;
        private readonly IExternalSnapshotRepo _externalSnapshotRepo;
        private readonly ILogger<DataIngestionService> _logger;

        public DataIngestionService(IMockSystemsClient mockSystemsClient, IExternalSnapshotRepo externalSnapshotRepo, ILogger<DataIngestionService> logger)
        {
            _mockSystemsClient = mockSystemsClient;
            _externalSnapshotRepo = externalSnapshotRepo;
            _logger = logger;
        }

        public async Task IngestAsync(Guid changeRequestId, Guid? mockCustomerId, Guid? mockProductId, Guid? mockVendorId, CancellationToken cancellationToken = default)
        {
            if (mockCustomerId is null && mockProductId is null && mockVendorId is null)
                return; // change type with no linked entity - nothing to snapshot.

            string? customerJson = null;
            string? productJson = null;
            string? vendorJson = null;

            try
            {
                if (mockCustomerId is Guid customerId)
                {
                    var customer = await _mockSystemsClient.GetCustomerAsync(customerId, cancellationToken);
                    if (customer is not null) customerJson = JsonSerializer.Serialize(customer);
                }
                if (mockProductId is Guid productId)
                {
                    var product = await _mockSystemsClient.GetProductAsync(productId, cancellationToken);
                    if (product is not null) productJson = JsonSerializer.Serialize(product);
                }
                if (mockVendorId is Guid vendorId)
                {
                    var vendor = await _mockSystemsClient.GetVendorAsync(vendorId, cancellationToken);
                    if (vendor is not null) vendorJson = JsonSerializer.Serialize(vendor);
                }
            }
            catch (HttpRequestException ex)
            {
                // Best-effort by design: Mock Systems being unreachable must not block intake -
                // Epic 1's own submission flow doesn't depend on this ecosystem being up. The
                // change request is still created; it just has no external context to ground the
                // category-mapping prompt with (CategoryMappingAiClient falls back to its
                // change-type-only prompt in that case).
                _logger.LogWarning(ex, "Data ingestion could not reach Mock Systems for change request {ChangeRequestId}.", changeRequestId);
                return;
            }

            if (customerJson is null && productJson is null && vendorJson is null)
                return; // linked ids were supplied but none resolved (e.g. stale ids) - nothing to persist.

            await _externalSnapshotRepo.SaveAsync(changeRequestId, mockCustomerId, customerJson, mockProductId, productJson, mockVendorId, vendorJson);
        }

        public Task<ExternalSnapshot?> GetSnapshotAsync(Guid changeRequestId, CancellationToken cancellationToken = default) =>
            _externalSnapshotRepo.GetByChangeRequestIdAsync(changeRequestId);
    }
}
