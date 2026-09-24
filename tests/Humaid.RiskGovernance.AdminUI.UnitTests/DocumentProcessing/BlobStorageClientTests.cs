namespace Humaid.RiskGovernance.AdminUI.UnitTests.DocumentProcessing
{
    using Humaid.RiskGovernance.AdminUI.Services.DocumentProcessing;
    using Microsoft.Extensions.Configuration;
    using Microsoft.Extensions.Hosting;
    using Moq;
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
        private static IHostEnvironment FakeEnvironment() => Mock.Of<IHostEnvironment>(e => e.EnvironmentName == "Development");

        [Fact]
        public void Constructor_DoesNotThrowWhenUnconfigured()
        {
            var exception = Record.Exception(() => new BlobStorageClient(EmptyConfiguration(), FakeEnvironment()));

            Assert.Null(exception);
        }

        [Fact]
        public async Task UploadAsync_ThrowsOnlyAtCallTimeWhenUnconfigured()
        {
            var sut = new BlobStorageClient(EmptyConfiguration(), FakeEnvironment());
            using var stream = new MemoryStream([1, 2, 3]);

            await Assert.ThrowsAsync<InvalidOperationException>(() => sut.UploadAsync("f.pdf", "application/pdf", stream));
        }

        /// <summary>
        /// Regression guard for a second real bug caught locally (PR #50 review): outside
        /// Production, ManagedIdentityCredential must be excluded from the DefaultAzureCredential
        /// chain, or it hard-fails on any dev machine with no IMDS and never falls through to
        /// AzureCliCredential - see BuildCredentialOptions's own comment.
        /// </summary>
        [Theory]
        [InlineData("Development", true)]
        [InlineData("Staging", true)]
        [InlineData("Production", false)]
        public void BuildCredentialOptions_ExcludesManagedIdentityOnlyOutsideProduction(string environmentName, bool expectedExcluded)
        {
            var environment = Mock.Of<IHostEnvironment>(e => e.EnvironmentName == environmentName);

            var options = BlobStorageClient.BuildCredentialOptions(environment);

            Assert.Equal(expectedExcluded, options.ExcludeManagedIdentityCredential);
        }
    }
}
