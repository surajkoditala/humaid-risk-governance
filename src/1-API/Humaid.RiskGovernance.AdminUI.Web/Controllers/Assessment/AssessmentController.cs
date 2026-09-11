namespace Humaid.RiskGovernance.AdminUI.Web.Controllers.Assessment
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Assessment;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Assessment;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core;
    using Humaid.RiskGovernance.AdminUI.Web.Controllers.Core;
    using Microsoft.AspNetCore.Authorization;
    using Microsoft.AspNetCore.Mvc;

    [Authorize]
    [Route("api/[controller]")]
    public class AssessmentController : BaseApiController
    {
        private readonly IAssessmentService _assessmentService;

        public AssessmentController(IAssessmentService assessmentService, ILogger<AssessmentController> logger)
            : base(logger)
        {
            _assessmentService = assessmentService;
        }

        [HttpPost("OpenWorkspace/{changeRequestId:guid}")]
        public Task<IActionResult> OpenWorkspace(Guid changeRequestId) =>
            ExecuteAsync(async () =>
            {
                var assessmentId = await _assessmentService.OpenWorkspaceAsync(changeRequestId);
                return OperationResult<Guid>.Success(assessmentId);
            }, "Failed to open assessment workspace.");

        [HttpGet("ByChangeRequest/{changeRequestId:guid}")]
        public Task<IActionResult> GetByChangeRequest(Guid changeRequestId) =>
            ExecuteAsync(async () =>
            {
                var assessment = await _assessmentService.GetByChangeRequestAsync(changeRequestId);
                return assessment is null
                    ? OperationResult<Infrastructure.Models.Assessment.Assessment>.NotFound("Assessment not found.")
                    : OperationResult<Infrastructure.Models.Assessment.Assessment>.Success(assessment);
            }, "Failed to fetch assessment.");

        [HttpGet("{assessmentId:guid}/Readiness")]
        public Task<IActionResult> GetReadiness(Guid assessmentId) =>
            ExecuteAsync(async () =>
            {
                var readiness = await _assessmentService.CheckReadinessAsync(assessmentId);
                return OperationResult<AssessmentReadiness>.Success(readiness);
            }, "Failed to check assessment readiness.");

        public record FinalizeBody(Guid ActorUserId);

        [HttpPost("{assessmentId:guid}/Finalize")]
        public Task<IActionResult> Finalize(Guid assessmentId, [FromBody] FinalizeBody body) =>
            ExecuteAsync(async () =>
            {
                try
                {
                    await _assessmentService.FinalizeAsync(assessmentId, body.ActorUserId);
                    return OperationResult<string>.Success("Finalized");
                }
                catch (InvalidOperationException ex)
                {
                    // US-6.3 AC1: lists what's outstanding rather than a generic failure.
                    return OperationResult<string>.BadRequest(ex.Message);
                }
            }, "Failed to finalize assessment.");
    }
}
