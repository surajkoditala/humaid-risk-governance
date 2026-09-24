namespace Humaid.RiskGovernance.AdminUI.UnitTests.DocumentProcessing
{
    using Humaid.RiskGovernance.AdminUI.Services.DocumentProcessing;
    using Microsoft.Extensions.Configuration;
    using Xunit;

    /// <summary>
    /// Regression guard for a real bug caught during Phase 3: BlobStorageClient originally
    /// validated BLOB_STORAGE_CONNECTION_STRING in its constructor. ChangeRequestService takes
    /// this client by constructor injection, so a blank connection string made *every*
    /// ChangeRequestController request fail at DI-resolution time, not just file uploads. Fixed by
    /// deferring the check to UploadAsync (call time) - same pattern ClaudeApiClient/
    /// MockSystemsClient already used. These two tests are what would have caught it.
    /// </summary>
    public class BlobStorageClientTests
    {
        private static IConfiguration EmptyConfiguration() => new ConfigurationBuilder().Build();

        private static IConfiguration ConfigurationWith(params (string Key, string Value)[] values) =>
            new ConfigurationBuilder()
                .AddInMemoryCollection(Array.ConvertAll(values, v => new KeyValuePair<string, string?>(v.Key, v.Value)))
                .Build();

        [Fact]
        public void Constructor_DoesNotThrowWhenUnconfigured()
        {
            var exception = Record.Exception(() => new BlobStorageClient(EmptyConfiguration()));

            Assert.Null(exception);
        }

        [Fact]
        public async Task UploadAsync_ThrowsOnlyAtCallTimeWhenUnconfigured()
        {
            var sut = new BlobStorageClient(EmptyConfiguration());
            using var stream = new MemoryStream([1, 2, 3]);

            await Assert.ThrowsAsync<InvalidOperationException>(() => sut.UploadAsync("f.pdf", "application/pdf", stream));
        }

        /// <summary>
        /// Regression guard for a real bug caught in PR #50 review: the exclusion rule originally
        /// keyed off IHostEnvironment.IsProduction(), but the only environment actually deployed
        /// today (Azure Container Apps dev) also sets ASPNETCORE_ENVIRONMENT=Development -
        /// identical to a developer's laptop - so that check couldn't tell a real container app
        /// (where Managed Identity is the correct, only working credential) apart from local dev
        /// (where it must be excluded to let AzureCliCredential run). CONTAINER_APP_NAME is what
        /// actually distinguishes them - see BuildCredentialOptions's own comment.
        /// </summary>
        [Fact]
        public void BuildCredentialOptions_ExcludesManagedIdentity_WhenContainerAppNameIsAbsent()
        {
            var options = BlobStorageClient.BuildCredentialOptions(EmptyConfiguration());

            Assert.True(options.ExcludeManagedIdentityCredential);
        }

        [Fact]
        public void BuildCredentialOptions_IncludesManagedIdentity_WhenContainerAppNameIsPresent()
        {
            var configuration = ConfigurationWith(("CONTAINER_APP_NAME", "ca-gh-hrg-workbench-dev"));

            var options = BlobStorageClient.BuildCredentialOptions(configuration);

            Assert.False(options.ExcludeManagedIdentityCredential);
        }
    }
}
