namespace Humaid.RiskGovernance.AdminUI.Web.Controllers.ChangeRequests
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.ChangeRequests;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.ChangeRequests;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core;
    using Humaid.RiskGovernance.AdminUI.Web.Controllers.Core;
    using Microsoft.AspNetCore.Authorization;
    using Microsoft.AspNetCore.Http;
    using Microsoft.AspNetCore.Mvc;

    /// <summary>Epic 1 - Change Request Intake.</summary>
    [Authorize]
    [Route("api/[controller]")]
    public class ChangeRequestController : BaseApiController
    {
        // NOTE: actions below take the acting user's id explicitly in the request body/route rather
        // than resolving it from the Auth0 access token's claims - that claim-to-app_user resolution
        // (and provisioning a new app_user on first login) is a noted extension point for the next
        // pass, not wired in this one. See docs/architecture/architecture-mapping.md.

        private readonly IChangeRequestService _changeRequestService;

        public ChangeRequestController(IChangeRequestService changeRequestService, ILogger<ChangeRequestController> logger)
            : base(logger)
        {
            _changeRequestService = changeRequestService;
        }

        [HttpPost("Submit")]
        public Task<IActionResult> Submit([FromBody] SubmitChangeRequestInput input) =>
            ExecuteAsync(async () =>
            {
                var created = await _changeRequestService.SubmitAsync(input);
                return OperationResult<ChangeRequest>.Success(created);
            }, "Failed to submit change request.");

        [HttpGet("{changeRequestId:guid}")]
        public Task<IActionResult> GetById(Guid changeRequestId) =>
            ExecuteAsync(async () =>
            {
                var request = await _changeRequestService.GetByIdAsync(changeRequestId);
                return request is null
                    ? OperationResult<ChangeRequest>.NotFound("Change request not found.")
                    : OperationResult<ChangeRequest>.Success(request);
            }, "Failed to fetch change request.");

        [HttpGet("ForUser/{userId:guid}")]
        public Task<IActionResult> GetForUser(Guid userId) =>
            ExecuteAsync(async () =>
            {
                var requests = await _changeRequestService.GetMyRequestsAsync(userId);
                return OperationResult<IReadOnlyList<ChangeRequestSummary>>.Success(requests);
            }, "Failed to fetch change requests.");

        /// <summary>The analyst inbox - every change request, not scoped to one submitter.</summary>
        [HttpGet]
        public Task<IActionResult> GetAll() =>
            ExecuteAsync(async () =>
            {
                var requests = await _changeRequestService.GetAllAsync();
                return OperationResult<IReadOnlyList<ChangeRequestSummary>>.Success(requests);
            }, "Failed to fetch change requests.");

        [HttpPost("AttachDocument")]
        public Task<IActionResult> AttachDocument([FromBody] AttachDocumentInput input) =>
            ExecuteAsync(async () =>
            {
                var (id, version) = await _changeRequestService.AttachDocumentAsync(input);
                return OperationResult<object>.Success(new { id, version });
            }, "Failed to attach document.");

        /// <summary>Phase 3 Step 4 - a real uploaded file (multipart), not pasted text. Uploads to
        /// blob storage and extracts its text server-side - see ChangeRequestService.AttachDocumentFileAsync.</summary>
        [HttpPost("AttachDocumentFile")]
        [RequestSizeLimit(25_000_000)]
        public Task<IActionResult> AttachDocumentFile(
            [FromForm] Guid changeRequestId, [FromForm] Guid uploadedByUserId, [FromForm] Guid? supersedesAttachmentId, IFormFile file) =>
            ExecuteAsync(async () =>
            {
                await using var stream = file.OpenReadStream();
                var (id, version) = await _changeRequestService.AttachDocumentFileAsync(
                    changeRequestId, file.FileName, file.ContentType, stream, uploadedByUserId, supersedesAttachmentId);
                return OperationResult<object>.Success(new { id, version });
            }, "Failed to attach document.");

        [HttpGet("{changeRequestId:guid}/Attachments")]
        public Task<IActionResult> GetAttachments(Guid changeRequestId) =>
            ExecuteAsync(async () =>
            {
                var attachments = await _changeRequestService.GetAttachmentsAsync(changeRequestId);
                return OperationResult<IReadOnlyList<ChangeRequestAttachment>>.Success(attachments);
            }, "Failed to fetch attachments.");

        public record RequestClarificationBody(Guid RequestedByUserId, string Question);

        [HttpPost("{changeRequestId:guid}/RequestClarification")]
        public Task<IActionResult> RequestClarification(Guid changeRequestId, [FromBody] RequestClarificationBody body) =>
            ExecuteAsync(async () =>
            {
                var id = await _changeRequestService.RequestClarificationAsync(changeRequestId, body.RequestedByUserId, body.Question);
                return OperationResult<Guid>.Success(id);
            }, "Failed to request clarification.");
    }
}
