namespace Humaid.RiskGovernance.AdminUI.Web.Controllers.DataIngestion
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.DataIngestion;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.DataIngestion;
    using Humaid.RiskGovernance.AdminUI.Web.Controllers.Core;
    using Microsoft.AspNetCore.Authorization;
    using Microsoft.AspNetCore.Mvc;

    /// <summary>
    /// Phase 3 - Intake's lookup dropdowns and the resulting snapshot. Proxies
    /// IMockSystemsClient/IDataIngestionService rather than the frontend calling Mock Systems
    /// directly, so the "only the Data Ingestion Layer reads Mock Systems" invariant holds for
    /// browsing the lookup lists too, not just for the actual ingest (see
    /// docs/architecture/architecture-mapping.md).
    /// </summary>
    [Authorize]
    [Route("api/[controller]")]
    public class DataIngestionController : BaseApiController
    {
        private readonly IMockSystemsClient _mockSystemsClient;
        private readonly IDataIngestionService _dataIngestionService;

        public DataIngestionController(IMockSystemsClient mockSystemsClient, IDataIngestionService dataIngestionService, ILogger<DataIngestionController> logger)
            : base(logger)
        {
            _mockSystemsClient = mockSystemsClient;
            _dataIngestionService = dataIngestionService;
        }

        [HttpGet("MockCustomers")]
        public Task<IActionResult> GetMockCustomers() =>
            ExecuteAsync(async () =>
            {
                var options = await _mockSystemsClient.ListCustomersAsync();
                return OperationResult<IReadOnlyList<MockLookupOption>>.Success(options);
            }, "Failed to fetch mock customers.");

        [HttpGet("MockProducts")]
        public Task<IActionResult> GetMockProducts() =>
            ExecuteAsync(async () =>
            {
                var options = await _mockSystemsClient.ListProductsAsync();
                return OperationResult<IReadOnlyList<MockLookupOption>>.Success(options);
            }, "Failed to fetch mock products.");

        [HttpGet("MockVendors")]
        public Task<IActionResult> GetMockVendors() =>
            ExecuteAsync(async () =>
            {
                var options = await _mockSystemsClient.ListVendorsAsync();
                return OperationResult<IReadOnlyList<MockLookupOption>>.Success(options);
            }, "Failed to fetch mock vendors.");

        [HttpGet("Snapshot/{changeRequestId:guid}")]
        public Task<IActionResult> GetSnapshot(Guid changeRequestId) =>
            ExecuteAsync(async () =>
            {
                var snapshot = await _dataIngestionService.GetSnapshotAsync(changeRequestId);
                return snapshot is null
                    ? OperationResult<ExternalSnapshot>.NotFound("No external snapshot linked to this change request.")
                    : OperationResult<ExternalSnapshot>.Success(snapshot);
            }, "Failed to fetch external snapshot.");
    }
}
