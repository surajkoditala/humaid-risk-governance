namespace Humaid.RiskGovernance.AdminUI.Web.Controllers.DocumentExtraction
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.DocumentExtraction;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.DocumentExtraction;
    using Humaid.RiskGovernance.AdminUI.Web.Controllers.Core;
    using Microsoft.AspNetCore.Authorization;
    using Microsoft.AspNetCore.Mvc;

    /// <summary>Epic 4 - AI-Assisted Document Extraction.</summary>
    [Authorize]
    [Route("api/[controller]")]
    public class DocumentExtractionController : BaseApiController
    {
        private readonly IDocumentExtractionService _documentExtractionService;

        public DocumentExtractionController(IDocumentExtractionService documentExtractionService, ILogger<DocumentExtractionController> logger)
            : base(logger)
        {
            _documentExtractionService = documentExtractionService;
        }

        public record ExtractRequest(Guid ChangeRequestId, Guid AttachmentId, string ChangeType, string DocumentText);

        /// <summary>US-4.1: real Claude call over the attachment's (already-extracted) plain text.</summary>
        [HttpPost("Extract")]
        public Task<IActionResult> Extract([FromBody] ExtractRequest request) =>
            ExecuteAsync(async () =>
            {
                var fields = await _documentExtractionService.ExtractAsync(
                    request.ChangeRequestId, request.AttachmentId, request.ChangeType, request.DocumentText);
                return OperationResult<IReadOnlyList<ExtractedField>>.Success(fields);
            }, "Failed to extract document fields.");

        public record CorrectRequest(CorrectExtractedFieldInput Input, bool IsMaterialChange);

        /// <summary>US-4.2: reason required only when <c>IsMaterialChange</c> is true.</summary>
        [HttpPost("Correct")]
        public Task<IActionResult> Correct([FromBody] CorrectRequest request) =>
            ExecuteAsync(async () =>
            {
                try
                {
                    var id = await _documentExtractionService.CorrectAsync(request.Input, request.IsMaterialChange);
                    return OperationResult<Guid>.Success(id);
                }
                catch (InvalidOperationException ex)
                {
                    return OperationResult<Guid>.BadRequest(ex.Message);
                }
            }, "Failed to correct extracted field.");

        [HttpGet("{changeRequestId:guid}")]
        public Task<IActionResult> GetFields(Guid changeRequestId) =>
            ExecuteAsync(async () =>
            {
                var fields = await _documentExtractionService.GetFieldsAsync(changeRequestId);
                return OperationResult<IReadOnlyList<ExtractedField>>.Success(fields);
            }, "Failed to fetch extracted fields.");
    }
}
