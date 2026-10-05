namespace Humaid.RiskGovernance.AdminUI.DA.Repos.DataIngestion
{
    using Dapper;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.DataIngestion;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.DataIngestion;

    /// <summary>Every method here calls one stored function - see
    /// Humaid.RiskGovernance.AdminUI.DB/functions/data_ingestion/.</summary>
    public class ExternalSnapshotRepo : IExternalSnapshotRepo
    {
        private readonly DapperConnectionFactory _connectionFactory;

        public ExternalSnapshotRepo(DapperConnectionFactory connectionFactory)
        {
            _connectionFactory = connectionFactory;
        }

        public async Task SaveAsync(Guid changeRequestId, Guid? mockCustomerId, string? customerRiskContextJson, Guid? mockProductId, string? productRiskContextJson, Guid? mockVendorId, string? vendorRiskContextJson)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            await conn.ExecuteAsync(
                @"SELECT * FROM func_saveExternalSnapshot(
                    @changeRequestId, @mockCustomerId, @customerRiskContextJson::jsonb,
                    @mockProductId, @productRiskContextJson::jsonb, @mockVendorId, @vendorRiskContextJson::jsonb)",
                new { changeRequestId, mockCustomerId, customerRiskContextJson, mockProductId, productRiskContextJson, mockVendorId, vendorRiskContextJson });
        }

        public async Task<ExternalSnapshot?> GetByChangeRequestIdAsync(Guid changeRequestId)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            return await conn.QuerySingleOrDefaultAsync<ExternalSnapshot>(
                "SELECT * FROM func_getExternalSnapshot(@changeRequestId)", new { changeRequestId });
        }
    }
}
