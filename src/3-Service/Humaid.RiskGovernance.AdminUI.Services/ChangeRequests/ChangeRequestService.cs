namespace Humaid.RiskGovernance.AdminUI.Services.ChangeRequests
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.ChangeRequests;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.ChangeRequests;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.DataIngestion;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.DocumentProcessing;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.ChangeRequests;

    public class ChangeRequestService : IChangeRequestService
    {
        // US-1.2 AC1: accept common formats, reject unsupported/unsafe ones with a clear message.
        private static readonly HashSet<string> SupportedContentTypes = new(StringComparer.OrdinalIgnoreCase)
        {
            "application/pdf",
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        };

        private readonly IChangeRequestRepo _changeRequestRepo;
        private readonly IDataIngestionService _dataIngestionService;
        private readonly IBlobStorageClient _blobStorageClient;
        private readonly IDocumentTextExtractor _documentTextExtractor;

        public ChangeRequestService(
            IChangeRequestRepo changeRequestRepo,
            IDataIngestionService dataIngestionService,
            IBlobStorageClient blobStorageClient,
            IDocumentTextExtractor documentTextExtractor)
        {
            _changeRequestRepo = changeRequestRepo;
            _dataIngestionService = dataIngestionService;
            _blobStorageClient = blobStorageClient;
            _documentTextExtractor = documentTextExtractor;
        }

        public async Task<ChangeRequest> SubmitAsync(SubmitChangeRequestInput input)
        {
            var created = await _changeRequestRepo.CreateAsync(input);

            // Phase 3 - Data Ingestion Layer. Best-effort: see DataIngestionService.IngestAsync for
            // why a Mock Systems outage must not fail intake.
            await _dataIngestionService.IngestAsync(created.Id, input.MockCustomerId, input.MockProductId, input.MockVendorId);

            return created;
        }

        public Task<ChangeRequest?> GetByIdAsync(Guid changeRequestId) => _changeRequestRepo.GetByIdAsync(changeRequestId);

        public Task<IReadOnlyList<ChangeRequestSummary>> GetMyRequestsAsync(Guid userId) => _changeRequestRepo.GetForUserAsync(userId);

        public Task<IReadOnlyList<ChangeRequestSummary>> GetAllAsync() => _changeRequestRepo.GetAllAsync();

        public Task<(Guid Id, int VersionNumber)> AttachDocumentAsync(AttachDocumentInput input)
        {
            if (!SupportedContentTypes.Contains(input.ContentType))
            {
                throw new InvalidOperationException(
                    $"Unsupported attachment type '{input.ContentType}'. Allowed: PDF, DOCX, XLSX.");
            }
            return _changeRequestRepo.AttachDocumentAsync(input);
        }

        public async Task<(Guid Id, int VersionNumber)> AttachDocumentFileAsync(
            Guid changeRequestId, string fileName, string contentType, Stream content, Guid uploadedByUserId, Guid? supersedesAttachmentId)
        {
            if (!SupportedContentTypes.Contains(contentType))
            {
                throw new InvalidOperationException(
                    $"Unsupported attachment type '{contentType}'. Allowed: PDF, DOCX, XLSX.");
            }

            // Extraction needs its own pass over the stream, so read it once into memory and give
            // each consumer (blob upload, text extractor) its own independently-seekable copy -
            // simpler and safer than juggling one Seek(0) between two async calls.
            using var buffer = new MemoryStream();
            await content.CopyToAsync(buffer);

            buffer.Position = 0;
            var storagePath = await _blobStorageClient.UploadAsync(fileName, contentType, buffer);

            buffer.Position = 0;
            var extractedText = await _documentTextExtractor.ExtractTextAsync(contentType, buffer);

            return await _changeRequestRepo.AttachDocumentAsync(new AttachDocumentInput
            {
                ChangeRequestId = changeRequestId,
                FileName = fileName,
                ContentType = contentType,
                StoragePath = storagePath,
                ExtractedText = extractedText,
                UploadedByUserId = uploadedByUserId,
                SupersedesAttachmentId = supersedesAttachmentId,
            });
        }

        public Task<IReadOnlyList<ChangeRequestAttachment>> GetAttachmentsAsync(Guid changeRequestId) =>
            _changeRequestRepo.GetAttachmentsAsync(changeRequestId);

        public Task<Guid> RequestClarificationAsync(Guid changeRequestId, Guid requestedByUserId, string question) =>
            _changeRequestRepo.RequestClarificationAsync(changeRequestId, requestedByUserId, question);
    }
}
