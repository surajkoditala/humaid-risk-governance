namespace Humaid.RiskGovernance.AdminUI.Web.Controllers.Sla
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Sla;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Sla;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Users;
    using Humaid.RiskGovernance.AdminUI.Web.Controllers.Core;
    using Microsoft.AspNetCore.Authorization;
    using Microsoft.AspNetCore.Mvc;

    /// <summary>
    /// Epic 19 - SLA tracking: configuration (Admin), per-request elapsed time, and the SLA view for
    /// Analysts and Admins. Informational only - nothing here changes a request's status or decides it.
    /// Role-restricted per action (Epic 11): Admin configures; Analyst and Admin read. Every action takes the
    /// acting user's id and calls RequireSelf first, so it must be the caller's own - never another user's.
    /// </summary>
    [Authorize]
    [Route("api/[controller]")]
    public class SlaController : BaseApiController
    {
        private readonly ISlaService _slaService;

        public SlaController(ISlaService slaService, ILogger<SlaController> logger)
            : base(logger)
        {
            _slaService = slaService;
        }

        /// <summary>US-19.1 AC1: targets, warning threshold and holiday calendar in plain, structured form.</summary>
        [HttpGet("Config")]
        [Authorize(Roles = AppRoles.AnalystOrAdmin)]
        public Task<IActionResult> GetConfig([FromQuery] Guid actorUserId) =>
            ExecuteAsync(async () =>
            {
                if (RequireSelf<SlaConfigView>(actorUserId) is { } forbidden) return forbidden;

                try
                {
                    return OperationResult<SlaConfigView>.Success(await _slaService.GetConfigAsync(actorUserId));
                }
                catch (ValidationException ex)
                {
                    return OperationResult<SlaConfigView>.BadRequest(ex.Message);
                }
            }, "Failed to fetch the SLA configuration.");

        /// <summary>US-19.1 AC2-AC5: a new versioned save with a mandatory reason. When stage targets exceed the
        /// end-to-end target the response has <c>saved: false</c> and the warnings - resend with
        /// <c>confirmWarnings: true</c> to accept them.</summary>
        [HttpPost("Config")]
        [Authorize(Roles = AppRoles.Admin)]
        public Task<IActionResult> SaveConfig([FromBody] SaveSlaConfigInput input) =>
            ExecuteAsync(async () =>
            {
                if (RequireSelf<SaveSlaConfigResult>(input.ActorUserId) is { } forbidden) return forbidden;

                try
                {
                    return OperationResult<SaveSlaConfigResult>.Success(await _slaService.SaveConfigAsync(input));
                }
                catch (ValidationException ex)
                {
                    return OperationResult<SaveSlaConfigResult>.BadRequest(ex.Message);
                }
            }, "Failed to save the SLA configuration.");

        [HttpPost("Holiday")]
        [Authorize(Roles = AppRoles.Admin)]
        public Task<IActionResult> AddHoliday([FromBody] AddSlaHolidayInput input) =>
            ExecuteAsync(async () =>
            {
                if (RequireSelf<Guid>(input.ActorUserId) is { } forbidden) return forbidden;

                try
                {
                    return OperationResult<Guid>.Success(await _slaService.AddHolidayAsync(input));
                }
                catch (ValidationException ex)
                {
                    return OperationResult<Guid>.BadRequest(ex.Message);
                }
            }, "Failed to add the holiday.");

        [HttpPost("Holiday/{holidayId:guid}/Remove")]
        [Authorize(Roles = AppRoles.Admin)]
        public Task<IActionResult> RemoveHoliday(Guid holidayId, [FromBody] RemoveSlaHolidayInput input) =>
            ExecuteAsync(async () =>
            {
                if (RequireSelf<string>(input.ActorUserId) is { } forbidden) return forbidden;

                try
                {
                    await _slaService.RemoveHolidayAsync(holidayId, input);
                    return OperationResult<string>.Success("Removed");
                }
                catch (ValidationException ex)
                {
                    return OperationResult<string>.BadRequest(ex.Message);
                }
            }, "Failed to remove the holiday.");

        /// <summary>US-19.5 AC1: open requests, most urgent first by default - paged, sortable and
        /// filterable (stage, type, state, search).</summary>
        [HttpGet("View")]
        [Authorize(Roles = AppRoles.AnalystOrAdmin)]
        public Task<IActionResult> GetView([FromQuery] SlaViewQuery query) =>
            ExecuteAsync(async () =>
            {
                if (RequireSelf<PagedResult<SlaViewRow>>(query.ActorUserId) is { } forbidden) return forbidden;

                try
                {
                    return OperationResult<PagedResult<SlaViewRow>>.Success(await _slaService.GetViewAsync(query));
                }
                catch (ValidationException ex)
                {
                    return OperationResult<PagedResult<SlaViewRow>>.BadRequest(ex.Message);
                }
            }, "Failed to fetch the SLA view.");

        /// <summary>Counts per SLA state for the grid's current stage / type / search filters.</summary>
        [HttpGet("Summary")]
        [Authorize(Roles = AppRoles.AnalystOrAdmin)]
        public Task<IActionResult> GetSummary([FromQuery] SlaViewQuery query) =>
            ExecuteAsync(async () =>
            {
                if (RequireSelf<IReadOnlyList<SlaStateCount>>(query.ActorUserId) is { } forbidden) return forbidden;

                try
                {
                    return OperationResult<IReadOnlyList<SlaStateCount>>.Success(await _slaService.GetSummaryAsync(query));
                }
                catch (ValidationException ex)
                {
                    return OperationResult<IReadOnlyList<SlaStateCount>>.BadRequest(ex.Message);
                }
            }, "Failed to fetch the SLA summary.");

        /// <summary>US-19.5 AC2-AC3: median / 90th-percentile cycle time and the share meeting their SLA.</summary>
        [HttpGet("Performance")]
        [Authorize(Roles = AppRoles.AnalystOrAdmin)]
        public Task<IActionResult> GetPerformance([FromQuery] Guid actorUserId, [FromQuery] string? changeType) =>
            ExecuteAsync(async () =>
            {
                if (RequireSelf<IReadOnlyList<SlaPerformanceRow>>(actorUserId) is { } forbidden) return forbidden;

                try
                {
                    return OperationResult<IReadOnlyList<SlaPerformanceRow>>.Success(
                        await _slaService.GetPerformanceAsync(actorUserId, changeType));
                }
                catch (ValidationException ex)
                {
                    return OperationResult<IReadOnlyList<SlaPerformanceRow>>.BadRequest(ex.Message);
                }
            }, "Failed to fetch SLA performance.");

        /// <summary>US-19.2 AC2: one request's elapsed time, target, due date and SLA state.</summary>
        [HttpGet("Request/{changeRequestId:guid}")]
        [Authorize(Roles = AppRoles.AnalystOrAdmin)]
        public Task<IActionResult> GetRequestSla(Guid changeRequestId, [FromQuery] Guid actorUserId) =>
            ExecuteAsync(async () =>
            {
                if (RequireSelf<IReadOnlyList<RequestSlaRow>>(actorUserId) is { } forbidden) return forbidden;

                try
                {
                    return OperationResult<IReadOnlyList<RequestSlaRow>>.Success(
                        await _slaService.GetRequestSlaAsync(actorUserId, changeRequestId));
                }
                catch (ValidationException ex)
                {
                    return OperationResult<IReadOnlyList<RequestSlaRow>>.BadRequest(ex.Message);
                }
            }, "Failed to fetch the request's SLA.");
    }
}
