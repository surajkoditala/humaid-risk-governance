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
        [InlineData("application/pdf", "f.pdf")]
        [InlineData("application/vnd.openxmlformats-officedocument.wordprocessingml.document", "f.docx")]
        [InlineData("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "f.xlsx")]
        public async Task AttachDocumentAsync_AcceptsSupportedContentTypes(string contentType, string fileName)
        {
            // DEF-006: the extension must agree with the declared content type now, not just the
            // content type alone - a bare "f" with no extension is exactly what a spoofed upload
            // looked like before that fix.
            var input = new AttachDocumentInput { ChangeRequestId = Guid.NewGuid(), FileName = fileName, ContentType = contentType, StoragePath = "dev://f" };
            _repo.Setup(r => r.AttachDocumentAsync(input)).ReturnsAsync((Guid.NewGuid(), 1));

            await _sut.AttachDocumentAsync(input);

            _repo.Verify(r => r.AttachDocumentAsync(input), Times.Once);
        }

        [Fact]
        public async Task AttachDocumentAsync_RejectsContentTypeExtensionMismatch()
        {
            // DEF-006: a file claiming to be a PDF but named .exe (or vice versa) must be rejected
            // even though "application/pdf" is itself an allowed content type.
            var input = new AttachDocumentInput { ChangeRequestId = Guid.NewGuid(), FileName = "malware.exe", ContentType = "application/pdf", StoragePath = "dev://f" };

            await Assert.ThrowsAsync<InvalidOperationException>(() => _sut.AttachDocumentAsync(input));
            _repo.Verify(r => r.AttachDocumentAsync(It.IsAny<AttachDocumentInput>()), Times.Never);
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
            // DEF-006: the service now sniffs the file's magic bytes ("%PDF" for a PDF), so the
            // fake upload content has to actually look like one.
            using var stream = new MemoryStream([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34]);

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
