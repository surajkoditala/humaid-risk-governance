namespace Humaid.RiskGovernance.AdminUI.UnitTests.DataIngestion
{
    using System.Net;
    using System.Text.Json;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.DataIngestion;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.DataIngestion;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.DataIngestion;
    using Humaid.RiskGovernance.AdminUI.Services.DataIngestion;
    using Microsoft.Extensions.Logging.Abstractions;
    using Moq;
    using Xunit;

    public class DataIngestionServiceTests
    {
        private readonly Mock<IMockSystemsClient> _mockSystemsClient = new();
        private readonly Mock<IExternalSnapshotRepo> _snapshotRepo = new();
        private readonly DataIngestionService _sut;

        public DataIngestionServiceTests()
        {
            _sut = new DataIngestionService(_mockSystemsClient.Object, _snapshotRepo.Object, NullLogger<DataIngestionService>.Instance);
        }

        [Fact]
        public async Task IngestAsync_IsANoOpWhenNoEntityWasLinkedAtIntake()
        {
            await _sut.IngestAsync(Guid.NewGuid(), null, null, null);

            _mockSystemsClient.Verify(c => c.GetCustomerAsync(It.IsAny<Guid>(), default), Times.Never);
            _snapshotRepo.Verify(r => r.SaveAsync(
                It.IsAny<Guid>(), It.IsAny<Guid?>(), It.IsAny<string?>(), It.IsAny<Guid?>(), It.IsAny<string?>(), It.IsAny<Guid?>(), It.IsAny<string?>()),
                Times.Never);
        }

        [Fact]
        public async Task IngestAsync_SavesASnapshotWhenTheCustomerResolves()
        {
            var changeRequestId = Guid.NewGuid();
            var customerId = Guid.NewGuid();
            _mockSystemsClient.Setup(c => c.GetCustomerAsync(customerId, default))
                .ReturnsAsync(new MockCustomerContext { Id = customerId, CustomerName = "Meridian Textiles Ltd" });

            await _sut.IngestAsync(changeRequestId, customerId, null, null);

            _snapshotRepo.Verify(r => r.SaveAsync(
                changeRequestId, customerId, It.Is<string>(j => j!.Contains("Meridian Textiles Ltd")), null, null, null, null),
                Times.Once);
        }

        [Fact]
        public async Task IngestAsync_SavesWhateverResolvedWhenOneOfTwoLinkedEntitiesIsNotFound()
        {
            var changeRequestId = Guid.NewGuid();
            var customerId = Guid.NewGuid();
            var staleProductId = Guid.NewGuid();
            _mockSystemsClient.Setup(c => c.GetCustomerAsync(customerId, default))
                .ReturnsAsync(new MockCustomerContext { Id = customerId, CustomerName = "Meridian Textiles Ltd" });
            _mockSystemsClient.Setup(c => c.GetProductAsync(staleProductId, default))
                .ReturnsAsync((MockProductContext?)null); // e.g. a stale/deleted id

            await _sut.IngestAsync(changeRequestId, customerId, staleProductId, null);

            _snapshotRepo.Verify(r => r.SaveAsync(
                changeRequestId, customerId, It.Is<string>(j => j!.Contains("Meridian Textiles Ltd")), staleProductId, null, null, null),
                Times.Once);
        }

        [Fact]
        public async Task IngestAsync_SwallowsMockSystemsOutageRatherThanFailingIntake()
        {
            var changeRequestId = Guid.NewGuid();
            var customerId = Guid.NewGuid();
            _mockSystemsClient.Setup(c => c.GetCustomerAsync(customerId, default))
                .ThrowsAsync(new HttpRequestException("connection refused", null, HttpStatusCode.ServiceUnavailable));

            // Must not throw - Epic 1 intake doesn't depend on Mock Systems being reachable.
            await _sut.IngestAsync(changeRequestId, customerId, null, null);

            _snapshotRepo.Verify(r => r.SaveAsync(
                It.IsAny<Guid>(), It.IsAny<Guid?>(), It.IsAny<string?>(), It.IsAny<Guid?>(), It.IsAny<string?>(), It.IsAny<Guid?>(), It.IsAny<string?>()),
                Times.Never);
        }

        [Fact]
        public async Task IngestAsync_SwallowsMockSystemsTimeoutRatherThanFailingIntake()
        {
            var customerId = Guid.NewGuid();
            // An HttpClient timeout surfaces as TaskCanceledException, not HttpRequestException.
            _mockSystemsClient.Setup(c => c.GetCustomerAsync(customerId, default))
                .ThrowsAsync(new TaskCanceledException("The request was canceled due to the configured HttpClient.Timeout"));

            await _sut.IngestAsync(Guid.NewGuid(), customerId, null, null);

            _snapshotRepo.Verify(r => r.SaveAsync(
                It.IsAny<Guid>(), It.IsAny<Guid?>(), It.IsAny<string?>(), It.IsAny<Guid?>(), It.IsAny<string?>(), It.IsAny<Guid?>(), It.IsAny<string?>()),
                Times.Never);
        }

        [Fact]
        public async Task IngestAsync_SwallowsMalformedMockSystemsResponseRatherThanFailingIntake()
        {
            var customerId = Guid.NewGuid();
            _mockSystemsClient.Setup(c => c.GetCustomerAsync(customerId, default))
                .ThrowsAsync(new JsonException("The JSON value could not be converted"));

            await _sut.IngestAsync(Guid.NewGuid(), customerId, null, null);

            _snapshotRepo.Verify(r => r.SaveAsync(
                It.IsAny<Guid>(), It.IsAny<Guid?>(), It.IsAny<string?>(), It.IsAny<Guid?>(), It.IsAny<string?>(), It.IsAny<Guid?>(), It.IsAny<string?>()),
                Times.Never);
        }

        [Fact]
        public async Task IngestAsync_StillPropagatesCancellationRequestedByTheCaller()
        {
            var customerId = Guid.NewGuid();
            using var cts = new CancellationTokenSource();
            cts.Cancel();
            _mockSystemsClient.Setup(c => c.GetCustomerAsync(customerId, cts.Token))
                .ThrowsAsync(new TaskCanceledException());

            await Assert.ThrowsAsync<TaskCanceledException>(() => _sut.IngestAsync(Guid.NewGuid(), customerId, null, null, cts.Token));
        }

        [Fact]
        public async Task GetSnapshotAsync_DelegatesToTheRepo()
        {
            var changeRequestId = Guid.NewGuid();
            var expected = new ExternalSnapshot { ChangeRequestId = changeRequestId };
            _snapshotRepo.Setup(r => r.GetByChangeRequestIdAsync(changeRequestId)).ReturnsAsync(expected);

            var result = await _sut.GetSnapshotAsync(changeRequestId);

            Assert.Same(expected, result);
        }
    }
}
