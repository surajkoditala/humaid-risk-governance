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
    }
}
