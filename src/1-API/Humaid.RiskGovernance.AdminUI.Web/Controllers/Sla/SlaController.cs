namespace Humaid.RiskGovernance.AdminUI.Web.Controllers.Sla
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Sla;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Sla;
    using Humaid.RiskGovernance.AdminUI.Web.Controllers.Core;
    using Microsoft.AspNetCore.Authorization;
    using Microsoft.AspNetCore.Mvc;

    /// <summary>
    /// Epic 19 - SLA tracking: configuration (Admin), per-request elapsed time, and the SLA view for
    /// Analysts and Admins. Informational only - nothing here changes a request's status or decides it.
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
        public Task<IActionResult> GetConfig([FromQuery] Guid actorUserId) =>
            ExecuteAsync(async () =>
            {
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
        public Task<IActionResult> SaveConfig([FromBody] SaveSlaConfigInput input) =>
            ExecuteAsync(async () =>
            {
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
        public Task<IActionResult> AddHoliday([FromBody] AddSlaHolidayInput input) =>
            ExecuteAsync(async () =>
            {
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
        public Task<IActionResult> RemoveHoliday(Guid holidayId, [FromBody] RemoveSlaHolidayInput input) =>
            ExecuteAsync(async () =>
            {
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

        /// <summary>US-19.5 AC1: open requests grouped by SLA state, most urgent first.</summary>
        [HttpGet("View")]
        public Task<IActionResult> GetView(
            [FromQuery] Guid actorUserId, [FromQuery] string? stage, [FromQuery] string? changeType, [FromQuery] string? state) =>
            ExecuteAsync(async () =>
            {
                try
                {
                    return OperationResult<IReadOnlyList<SlaViewRow>>.Success(
                        await _slaService.GetViewAsync(actorUserId, stage, changeType, state));
                }
                catch (ValidationException ex)
                {
                    return OperationResult<IReadOnlyList<SlaViewRow>>.BadRequest(ex.Message);
                }
            }, "Failed to fetch the SLA view.");

        /// <summary>US-19.5 AC2-AC3: median / 90th-percentile cycle time and the share meeting their SLA.</summary>
        [HttpGet("Performance")]
        public Task<IActionResult> GetPerformance([FromQuery] Guid actorUserId, [FromQuery] string? changeType) =>
            ExecuteAsync(async () =>
            {
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
        public Task<IActionResult> GetRequestSla(Guid changeRequestId, [FromQuery] Guid actorUserId) =>
            ExecuteAsync(async () =>
            {
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
