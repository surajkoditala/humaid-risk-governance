namespace Humaid.RiskGovernance.AdminUI.Services.DataIngestion
{
    using System.Net.Http.Json;
    using System.Text.Json;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.DataIngestion;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.DataIngestion;
    using Microsoft.Extensions.Http;

    /// <summary>
    /// Thin HTTP client for Humaid.RiskGovernance.MockSystems - same "one explicit client per
    /// external dependency" pattern as ClaudeApiClient. Named HttpClient "MockSystems" is
    /// registered in Program.cs.
    /// </summary>
    public class MockSystemsClient : IMockSystemsClient
    {
        private static readonly JsonSerializerOptions JsonOptions = new() { PropertyNameCaseInsensitive = true };

        private readonly HttpClient _httpClient;

        public MockSystemsClient(IHttpClientFactory httpClientFactory)
        {
            _httpClient = httpClientFactory.CreateClient("MockSystems");
        }

        public async Task<IReadOnlyList<MockLookupOption>> ListCustomersAsync(CancellationToken cancellationToken = default)
        {
            var rows = await _httpClient.GetFromJsonAsync<List<CustomerRow>>("/api/customers", JsonOptions, cancellationToken) ?? [];
            return rows.Select(r => new MockLookupOption { Id = r.Id, Label = r.CustomerName }).ToList();
        }

        public async Task<IReadOnlyList<MockLookupOption>> ListProductsAsync(CancellationToken cancellationToken = default)
        {
            var rows = await _httpClient.GetFromJsonAsync<List<ProductRow>>("/api/products", JsonOptions, cancellationToken) ?? [];
            return rows.Select(r => new MockLookupOption { Id = r.Id, Label = r.ProductName }).ToList();
        }

        public async Task<IReadOnlyList<MockLookupOption>> ListVendorsAsync(CancellationToken cancellationToken = default)
        {
            var rows = await _httpClient.GetFromJsonAsync<List<VendorRow>>("/api/vendors", JsonOptions, cancellationToken) ?? [];
            return rows.Select(r => new MockLookupOption { Id = r.Id, Label = r.VendorName }).ToList();
        }

        public async Task<MockCustomerContext?> GetCustomerAsync(Guid id, CancellationToken cancellationToken = default)
        {
            var row = await GetOrNullAsync<CustomerRow>($"/api/customers/{id}", cancellationToken);
            return row is null ? null : new MockCustomerContext
            {
                Id = row.Id,
                CustomerName = row.CustomerName,
                CustomerType = row.CustomerType,
                CustomerGeography = row.CustomerGeography,
                SegmentClassification = row.SegmentClassification,
                KycStatus = row.KycStatus,
            };
        }

        public async Task<MockProductContext?> GetProductAsync(Guid id, CancellationToken cancellationToken = default)
        {
            var row = await GetOrNullAsync<ProductRow>($"/api/products/{id}", cancellationToken);
            return row is null ? null : new MockProductContext
            {
                Id = row.Id,
                ProductName = row.ProductName,
                ProductType = row.ProductType,
                ProductGeography = row.ProductGeography,
                LaunchChangeType = row.LaunchChangeType,
            };
        }

        public async Task<MockVendorContext?> GetVendorAsync(Guid id, CancellationToken cancellationToken = default)
        {
            var row = await GetOrNullAsync<VendorRow>($"/api/vendors/{id}", cancellationToken);
            return row is null ? null : new MockVendorContext
            {
                Id = row.Id,
                VendorName = row.VendorName,
                VendorRiskRating = row.VendorRiskRating,
                VendorJurisdiction = row.VendorJurisdiction,
                DataAccessScope = row.DataAccessScope,
                CertificationStatus = row.CertificationStatus,
            };
        }

        public async Task PushCustomerRiskFlagAsync(Guid id, string riskFlag, CancellationToken cancellationToken = default)
        {
            var response = await _httpClient.PostAsJsonAsync($"/api/customers/{id}/risk-flag", new { riskFlag }, cancellationToken);
            response.EnsureSuccessStatusCode();
        }

        public async Task PushProductRiskFlagAsync(Guid id, bool goLive, string riskRating, CancellationToken cancellationToken = default)
        {
            var response = await _httpClient.PostAsJsonAsync($"/api/products/{id}/risk-flag", new { goLive, riskRating }, cancellationToken);
            response.EnsureSuccessStatusCode();
        }

        public async Task PushVendorRiskFlagAsync(Guid id, string updatedRiskRating, CancellationToken cancellationToken = default)
        {
            var response = await _httpClient.PostAsJsonAsync($"/api/vendors/{id}/risk-flag", new { updatedRiskRating }, cancellationToken);
            response.EnsureSuccessStatusCode();
        }

        private async Task<T?> GetOrNullAsync<T>(string requestUri, CancellationToken cancellationToken)
        {
            var response = await _httpClient.GetAsync(requestUri, cancellationToken);
            if (!response.IsSuccessStatusCode) return default;
            return await response.Content.ReadFromJsonAsync<T>(JsonOptions, cancellationToken);
        }

        private class CustomerRow
        {
            public Guid Id { get; set; }
            public string CustomerName { get; set; } = string.Empty;
            public string CustomerType { get; set; } = string.Empty;
            public string CustomerGeography { get; set; } = string.Empty;
            public string SegmentClassification { get; set; } = string.Empty;
            public string KycStatus { get; set; } = string.Empty;
        }

        private class ProductRow
        {
            public Guid Id { get; set; }
            public string ProductName { get; set; } = string.Empty;
            public string ProductType { get; set; } = string.Empty;
            public string ProductGeography { get; set; } = string.Empty;
            public string LaunchChangeType { get; set; } = string.Empty;
        }

        private class VendorRow
        {
            public Guid Id { get; set; }
            public string VendorName { get; set; } = string.Empty;
            public string VendorRiskRating { get; set; } = string.Empty;
            public string VendorJurisdiction { get; set; } = string.Empty;
            public string DataAccessScope { get; set; } = string.Empty;
            public string CertificationStatus { get; set; } = string.Empty;
        }
    }
}
