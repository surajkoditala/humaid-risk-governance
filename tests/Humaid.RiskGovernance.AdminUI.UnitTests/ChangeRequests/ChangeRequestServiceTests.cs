namespace Humaid.RiskGovernance.AdminUI.UnitTests.ChangeRequests
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.ChangeRequests;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.DataIngestion;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.DocumentProcessing;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.ChangeRequests;
    using Humaid.RiskGovernance.AdminUI.Services.ChangeRequests;
    using Moq;
    using Xunit;

    public class ChangeRequestServiceTests
    {
        private readonly Mock<IChangeRequestRepo> _repo = new();
        private readonly Mock<IDataIngestionService> _dataIngestionService = new();
        private readonly Mock<IBlobStorageClient> _blobStorageClient = new();
        private readonly Mock<IDocumentTextExtractor> _documentTextExtractor = new();
        private readonly ChangeRequestService _sut;

        public ChangeRequestServiceTests()
        {
            _sut = new ChangeRequestService(_repo.Object, _dataIngestionService.Object, _blobStorageClient.Object, _documentTextExtractor.Object);
        }

        [Fact]
        public async Task SubmitAsync_TriggersDataIngestionWithTheLinkedMockSystemIds()
        {
            var changeRequestId = Guid.NewGuid();
            var customerId = Guid.NewGuid();
            var input = new SubmitChangeRequestInput { ChangeType = "CustomerSegment", Title = "t", Description = "d", SubmittedByUserId = Guid.NewGuid(), MockCustomerId = customerId };
            _repo.Setup(r => r.CreateAsync(input)).ReturnsAsync(new ChangeRequest { Id = changeRequestId });

            await _sut.SubmitAsync(input);

            _dataIngestionService.Verify(s => s.IngestAsync(changeRequestId, customerId, null, null, default), Times.Once);
        }

        [Theory]
        [InlineData("application/pdf")]
        [InlineData("application/vnd.openxmlformats-officedocument.wordprocessingml.document")]
        [InlineData("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")]
        public async Task AttachDocumentAsync_AcceptsSupportedContentTypes(string contentType)
        {
            var input = new AttachDocumentInput { ChangeRequestId = Guid.NewGuid(), FileName = "f", ContentType = contentType, StoragePath = "dev://f" };
            _repo.Setup(r => r.AttachDocumentAsync(input)).ReturnsAsync((Guid.NewGuid(), 1));

            await _sut.AttachDocumentAsync(input);

            _repo.Verify(r => r.AttachDocumentAsync(input), Times.Once);
        }

        [Fact]
        public async Task AttachDocumentAsync_RejectsUnsupportedContentType()
        {
            var input = new AttachDocumentInput { ChangeRequestId = Guid.NewGuid(), FileName = "f.exe", ContentType = "application/x-msdownload", StoragePath = "dev://f" };

            await Assert.ThrowsAsync<InvalidOperationException>(() => _sut.AttachDocumentAsync(input));
            _repo.Verify(r => r.AttachDocumentAsync(It.IsAny<AttachDocumentInput>()), Times.Never);
        }

        [Fact]
        public async Task AttachDocumentFileAsync_RejectsUnsupportedContentType_WithoutTouchingBlobStorage()
        {
            var changeRequestId = Guid.NewGuid();
            using var stream = new MemoryStream([1, 2, 3]);

            await Assert.ThrowsAsync<InvalidOperationException>(() =>
                _sut.AttachDocumentFileAsync(changeRequestId, "malware.exe", "application/x-msdownload", stream, Guid.NewGuid(), null));

            _blobStorageClient.Verify(b => b.UploadAsync(It.IsAny<string>(), It.IsAny<string>(), It.IsAny<Stream>(), default), Times.Never);
        }

        [Fact]
        public async Task AttachDocumentFileAsync_UploadsThenExtractsThenPersistsTheResult()
        {
            var changeRequestId = Guid.NewGuid();
            var uploadedByUserId = Guid.NewGuid();
            const string contentType = "application/pdf";
            using var stream = new MemoryStream([1, 2, 3]);

            _blobStorageClient.Setup(b => b.UploadAsync("brief.pdf", contentType, It.IsAny<Stream>(), default))
                .ReturnsAsync("https://blob/brief.pdf");
            _documentTextExtractor.Setup(e => e.ExtractTextAsync(contentType, It.IsAny<Stream>(), default))
                .ReturnsAsync("extracted text");
            _repo.Setup(r => r.AttachDocumentAsync(It.IsAny<AttachDocumentInput>())).ReturnsAsync((Guid.NewGuid(), 1));

            await _sut.AttachDocumentFileAsync(changeRequestId, "brief.pdf", contentType, stream, uploadedByUserId, null);

            _repo.Verify(r => r.AttachDocumentAsync(It.Is<AttachDocumentInput>(i =>
                i.ChangeRequestId == changeRequestId &&
                i.StoragePath == "https://blob/brief.pdf" &&
                i.ExtractedText == "extracted text" &&
                i.UploadedByUserId == uploadedByUserId)), Times.Once);
        }
    }
}
