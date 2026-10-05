namespace Humaid.RiskGovernance.AdminUI.Web.Controllers.ChangeRequests
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.ChangeRequests;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.ChangeRequests;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Users;
    using Humaid.RiskGovernance.AdminUI.Web.Auth;
    using Humaid.RiskGovernance.AdminUI.Web.Controllers.Core;
    using Microsoft.AspNetCore.Authorization;
    using Microsoft.AspNetCore.Http;
    using Microsoft.AspNetCore.Mvc;

    /// <summary>Epic 1 - Change Request Intake.</summary>
    [Authorize]
    [Route("api/[controller]")]
    public class ChangeRequestController : BaseApiController
    {
        // NOTE: actions below still take the acting user's id explicitly in the request body/form
        // rather than reading it from the access token - see docs/governance/access-control-matrix.md.
        // Epic 11 makes that field trustworthy: every action that takes one calls RequireSelf(...)
        // first, which rejects the call unless that id is the caller's own (from AppUserClaimsTransformation,
        // never from the request itself). A Product Owner may only act on their own change requests -
        // enforced below by comparing the fetched request's SubmittedByUserId to the caller.

        private readonly IChangeRequestService _changeRequestService;

        public ChangeRequestController(IChangeRequestService changeRequestService, ILogger<ChangeRequestController> logger)
            : base(logger)
        {
            _changeRequestService = changeRequestService;
        }

        [HttpPost("Submit")]
        [Authorize(Roles = AppRoles.ProductOwner)]
        public Task<IActionResult> Submit([FromBody] SubmitChangeRequestInput input) =>
            ExecuteAsync(async () =>
            {
                if (RequireSelf<ChangeRequest>(input.SubmittedByUserId) is { } forbidden) return forbidden;

                try
                {
                    var created = await _changeRequestService.SubmitAsync(input);
                    return OperationResult<ChangeRequest>.Success(created);
                }
                catch (ValidationException ex)
                {
                    return OperationResult<ChangeRequest>.BadRequest(ex.Message);
                }
            }, "Failed to submit change request.");

        [HttpGet("{changeRequestId:guid}")]
        [Authorize(Roles = AppRoles.ProductOwnerOrAnalyst)]
        public Task<IActionResult> GetById(Guid changeRequestId) =>
            ExecuteAsync(async () =>
            {
                var request = await _changeRequestService.GetByIdAsync(changeRequestId);
                if (request is null)
                    return OperationResult<ChangeRequest>.NotFound("Change request not found.");
                if (IsOwnershipRestricted() && request.SubmittedByUserId != User.GetAppUserId())
                    return OperationResult<ChangeRequest>.Forbidden("You can only view your own change requests.");

                return OperationResult<ChangeRequest>.Success(request);
            }, "Failed to fetch change request.");

        [HttpGet("ForUser/{userId:guid}")]
        [Authorize(Roles = AppRoles.ProductOwner)]
        public Task<IActionResult> GetForUser(Guid userId, [FromQuery] GridQuery query) =>
            ExecuteAsync(async () =>
            {
                if (RequireSelf<PagedResult<ChangeRequestSummary>>(userId) is { } forbidden) return forbidden;

                var requests = await _changeRequestService.GetMyRequestsAsync(userId, query);
                return OperationResult<PagedResult<ChangeRequestSummary>>.Success(requests);
            }, "Failed to fetch change requests.");

        /// <summary>The analyst inbox - every change request, not scoped to one submitter.</summary>
        [HttpGet]
        [Authorize(Roles = AppRoles.Analyst)]
        public Task<IActionResult> GetAll([FromQuery] GridQuery query) =>
            ExecuteAsync(async () =>
            {
                var requests = await _changeRequestService.GetAllAsync(query);
                return OperationResult<PagedResult<ChangeRequestSummary>>.Success(requests);
            }, "Failed to fetch change requests.");

        [HttpPost("AttachDocument")]
        [Authorize(Roles = AppRoles.ProductOwner)]
        public Task<IActionResult> AttachDocument([FromBody] AttachDocumentInput input) =>
            ExecuteAsync(async () =>
            {
                if (RequireSelf<object>(input.UploadedByUserId) is { } forbidden) return forbidden;
                if (await OwnershipCheckAsync<object>(input.ChangeRequestId) is { } notOwner) return notOwner;

                try
                {
                    var (id, version) = await _changeRequestService.AttachDocumentAsync(input);
                    return OperationResult<object>.Success(new { id, version });
                }
                catch (ValidationException ex)
                {
                    return OperationResult<object>.BadRequest(ex.Message);
                }
            }, "Failed to attach document.");

        /// <summary>Phase 3 Step 4 - a real uploaded file (multipart), not pasted text. Uploads to
        /// blob storage and extracts its text server-side - see ChangeRequestService.AttachDocumentFileAsync.</summary>
        [HttpPost("AttachDocumentFile")]
        [Authorize(Roles = AppRoles.ProductOwner)]
        [RequestSizeLimit(25_000_000)]
        public Task<IActionResult> AttachDocumentFile(
            [FromForm] Guid changeRequestId, [FromForm] Guid uploadedByUserId, [FromForm] Guid? supersedesAttachmentId, IFormFile file) =>
            ExecuteAsync(async () =>
            {
                if (RequireSelf<object>(uploadedByUserId) is { } forbidden) return forbidden;
                if (await OwnershipCheckAsync<object>(changeRequestId) is { } notOwner) return notOwner;

                try
                {
                    await using var stream = file.OpenReadStream();
                    var (id, version) = await _changeRequestService.AttachDocumentFileAsync(
                        changeRequestId, file.FileName, file.ContentType, stream, uploadedByUserId, supersedesAttachmentId);
                    return OperationResult<object>.Success(new { id, version });
                }
                catch (ValidationException ex)
                {
                    return OperationResult<object>.BadRequest(ex.Message);
                }
            }, "Failed to attach document.");

        [HttpGet("{changeRequestId:guid}/Attachments")]
        [Authorize(Roles = AppRoles.ProductOwnerOrAnalyst)]
        public Task<IActionResult> GetAttachments(Guid changeRequestId) =>
            ExecuteAsync(async () =>
            {
                if (IsOwnershipRestricted() &&
                    await OwnershipCheckAsync<IReadOnlyList<ChangeRequestAttachment>>(changeRequestId) is { } notOwner)
                    return notOwner;

                var attachments = await _changeRequestService.GetAttachmentsAsync(changeRequestId);
                return OperationResult<IReadOnlyList<ChangeRequestAttachment>>.Success(attachments);
            }, "Failed to fetch attachments.");

        public record RequestClarificationBody(Guid RequestedByUserId, string Question);

        /// <summary>Analyst-initiated: US-1.3 AC3 describes the Product Owner seeing "what is being
        /// asked and by whom" once an analyst has sent a request back for clarification.</summary>
        [HttpPost("{changeRequestId:guid}/RequestClarification")]
        [Authorize(Roles = AppRoles.Analyst)]
        public Task<IActionResult> RequestClarification(Guid changeRequestId, [FromBody] RequestClarificationBody body) =>
            ExecuteAsync(async () =>
            {
                if (RequireSelf<Guid>(body.RequestedByUserId) is { } forbidden) return forbidden;

                var id = await _changeRequestService.RequestClarificationAsync(changeRequestId, body.RequestedByUserId, body.Question);
                return OperationResult<Guid>.Success(id);
            }, "Failed to request clarification.");

        /// <summary>True only when the caller is a Product Owner and not also an Analyst - a
        /// multi-role user (e.g. the seeded "QA Full Access" account, or any real user holding
        /// both roles) should get the Analyst-level "see everything" behavior, not be scoped down
        /// to their own submissions just because they also happen to hold ProductOwner.</summary>
        private bool IsOwnershipRestricted() =>
            User.IsInRole(AppRoles.ProductOwner) && !User.IsInRole(AppRoles.Analyst);

        private async Task<OperationResult<T>?> OwnershipCheckAsync<T>(Guid changeRequestId)
        {
            var request = await _changeRequestService.GetByIdAsync(changeRequestId);
            if (request is null)
                return OperationResult<T>.NotFound("Change request not found.");
            if (request.SubmittedByUserId != User.GetAppUserId())
                return OperationResult<T>.Forbidden("You can only act on your own change requests.");
            return null;
        }
    }
}
