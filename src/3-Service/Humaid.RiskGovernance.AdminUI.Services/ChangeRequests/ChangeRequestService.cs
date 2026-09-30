namespace Humaid.RiskGovernance.AdminUI.Services.ChangeRequests
{
    using System.Text.Json;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.ChangeRequests;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.ChangeRequests;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.DataIngestion;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.DocumentProcessing;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.ChangeRequests;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core;

    public class ChangeRequestService : IChangeRequestService
    {
        // US-1.2 AC1: accept common formats, reject unsupported/unsafe ones with a clear message.
        private static readonly HashSet<string> SupportedContentTypes = new(StringComparer.OrdinalIgnoreCase)
        {
            "application/pdf",
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        };

        // DEF-006: the browser/client supplies Content-Type, so it cannot be trusted on its own -
        // a renamed .exe sent as "application/pdf" passed the old check. Extension and, where we
        // have the actual bytes (AttachDocumentFileAsync), the file's magic-byte signature must
        // agree with the declared content type before it's accepted.
        private static readonly Dictionary<string, string> RequiredExtensionByContentType = new(StringComparer.OrdinalIgnoreCase)
        {
            ["application/pdf"] = ".pdf",
            ["application/vnd.openxmlformats-officedocument.wordprocessingml.document"] = ".docx",
            ["application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"] = ".xlsx",
        };

        private static readonly byte[] PdfSignature = { 0x25, 0x50, 0x44, 0x46 }; // "%PDF"
        private static readonly byte[] ZipSignature = { 0x50, 0x4B }; // "PK" - DOCX/XLSX are both OOXML zip packages

        private static void ValidateAttachmentTypeOrThrow(string fileName, string contentType)
        {
            if (!SupportedContentTypes.Contains(contentType) ||
                !RequiredExtensionByContentType.TryGetValue(contentType, out var requiredExtension) ||
                !fileName.EndsWith(requiredExtension, StringComparison.OrdinalIgnoreCase))
            {
                throw new ValidationException(
                    $"Unsupported attachment type for '{fileName}'. Allowed: PDF, DOCX, XLSX.");
            }
        }

        private static void ValidateAttachmentSignatureOrThrow(string fileName, string contentType, ReadOnlySpan<byte> headerBytes)
        {
            var expectedSignature = contentType.Equals("application/pdf", StringComparison.OrdinalIgnoreCase) ? PdfSignature : ZipSignature;
            if (headerBytes.Length < expectedSignature.Length || !headerBytes[..expectedSignature.Length].SequenceEqual(expectedSignature))
            {
                throw new ValidationException(
                    $"File '{fileName}' does not match its declared type. Allowed: PDF, DOCX, XLSX.");
            }
        }

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

        // DEF-009: SubmitChangeRequestInput had no validation - only the SPA checked - so a request
        // with a blank title/description, an unrecognised change type, or a 20,000-character title
        // was created without complaint. US-1.1 AC3 requires the system itself to block submission
        // and list what's missing.
        private static readonly HashSet<string> ValidChangeTypes = new(StringComparer.Ordinal)
        {
            "Product", "Feature", "Process", "Vendor", "Geography", "CustomerSegment",
        };

        private const int MaxTitleLength = 500;
        private const int MaxDescriptionLength = 10_000;

        // DEF-024: Vendor and Geography requests showed the same generic free-text box, with no
        // vendor name/jurisdiction/data-access-scope or target country/region fields. Intake.jsx
        // now renders these as structured inputs and puts them in typeSpecificFieldsJson under
        // these keys - enforce them server-side too, not just in the SPA.
        private static readonly Dictionary<string, string[]> RequiredTypeSpecificFields = new(StringComparer.Ordinal)
        {
            ["Vendor"] = new[] { "vendorName", "jurisdiction", "dataAccessScope" },
            ["Geography"] = new[] { "targetCountryRegion" },
        };

        private static void ValidateSubmitInputOrThrow(SubmitChangeRequestInput input)
        {
            var missing = new List<string>();
            if (string.IsNullOrWhiteSpace(input.ChangeType) || !ValidChangeTypes.Contains(input.ChangeType))
                missing.Add("changeType");
            if (string.IsNullOrWhiteSpace(input.Title))
                missing.Add("title");
            if (string.IsNullOrWhiteSpace(input.Description))
                missing.Add("description");

            if (missing.Count == 0 && RequiredTypeSpecificFields.TryGetValue(input.ChangeType, out var requiredFields))
            {
                var typeSpecificValues = TryParseTypeSpecificFields(input.TypeSpecificFieldsJson);
                foreach (var field in requiredFields)
                {
                    if (!typeSpecificValues.TryGetValue(field, out var value) || string.IsNullOrWhiteSpace(value))
                        missing.Add(field);
                }
            }

            if (missing.Count > 0)
                throw new ValidationException($"Missing or invalid required field(s): {string.Join(", ", missing)}.");

            if (input.Title.Length > MaxTitleLength)
                throw new ValidationException($"Title must be {MaxTitleLength} characters or fewer.");
            if (input.Description.Length > MaxDescriptionLength)
                throw new ValidationException($"Description must be {MaxDescriptionLength} characters or fewer.");
        }

        private static Dictionary<string, string> TryParseTypeSpecificFields(string typeSpecificFieldsJson)
        {
            var result = new Dictionary<string, string>(StringComparer.Ordinal);
            if (string.IsNullOrWhiteSpace(typeSpecificFieldsJson))
                return result;

            try
            {
                using var doc = JsonDocument.Parse(typeSpecificFieldsJson);
                foreach (var property in doc.RootElement.EnumerateObject())
                {
                    if (property.Value.ValueKind == JsonValueKind.String)
                        result[property.Name] = property.Value.GetString() ?? string.Empty;
                }
            }
            catch (JsonException)
            {
                // Malformed JSON is treated the same as "field not present" - the missing-field
                // list below will name the required fields rather than surfacing a parser error.
            }

            return result;
        }

        public async Task<ChangeRequest> SubmitAsync(SubmitChangeRequestInput input)
        {
            ValidateSubmitInputOrThrow(input);

            var created = await _changeRequestRepo.CreateAsync(input);

            // Phase 3 - Data Ingestion Layer. Best-effort: see DataIngestionService.IngestAsync for
            // why a Mock Systems outage must not fail intake.
            await _dataIngestionService.IngestAsync(created.Id, input.MockCustomerId, input.MockProductId, input.MockVendorId);

            return created;
        }

        public Task<ChangeRequest?> GetByIdAsync(Guid changeRequestId) => _changeRequestRepo.GetByIdAsync(changeRequestId);

        public Task<PagedResult<ChangeRequestSummary>> GetMyRequestsAsync(Guid userId, GridQuery query) => _changeRequestRepo.GetForUserAsync(userId, query);

        public Task<PagedResult<ChangeRequestSummary>> GetAllAsync(GridQuery query) => _changeRequestRepo.GetAllAsync(query);

        public Task<(Guid Id, int VersionNumber)> AttachDocumentAsync(AttachDocumentInput input)
        {
            ValidateAttachmentTypeOrThrow(input.FileName, input.ContentType);
            return _changeRequestRepo.AttachDocumentAsync(input);
        }

        public async Task<(Guid Id, int VersionNumber)> AttachDocumentFileAsync(
            Guid changeRequestId, string fileName, string contentType, Stream content, Guid uploadedByUserId, Guid? supersedesAttachmentId)
        {
            ValidateAttachmentTypeOrThrow(fileName, contentType);

            // Extraction needs its own pass over the stream, so read it once into memory and give
            // each consumer (blob upload, text extractor) its own independently-seekable copy -
            // simpler and safer than juggling one Seek(0) between two async calls.
            using var buffer = new MemoryStream();
            await content.CopyToAsync(buffer);

            buffer.Position = 0;
            var header = new byte[Math.Min(4, buffer.Length)];
            _ = buffer.Read(header, 0, header.Length);
            ValidateAttachmentSignatureOrThrow(fileName, contentType, header);

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
