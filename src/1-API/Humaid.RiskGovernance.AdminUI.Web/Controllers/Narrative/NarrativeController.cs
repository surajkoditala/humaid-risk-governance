namespace Humaid.RiskGovernance.AdminUI.Web.Controllers.Narrative
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Narrative;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Narrative;
    using Humaid.RiskGovernance.AdminUI.Web.Controllers.Core;
    using Microsoft.AspNetCore.Authorization;
    using Microsoft.AspNetCore.Mvc;

    /// <summary>Epic 5 - AI-Drafted Risk Assessment narrative.</summary>
    [Authorize]
    [Route("api/[controller]")]
    public class NarrativeController : BaseApiController
    {
        private readonly INarrativeService _narrativeService;

        public NarrativeController(INarrativeService narrativeService, ILogger<NarrativeController> logger)
            : base(logger)
        {
            _narrativeService = narrativeService;
        }

        public record DraftRequest(Guid AssessmentId, Guid RiskCategoryId, string? RegenerationFeedback);

        /// <summary>US-5.1 (first draft, RegenerationFeedback null) / US-5.2 (regenerate, feedback supplied).</summary>
        [HttpPost("Draft")]
        public Task<IActionResult> Draft([FromBody] DraftRequest request) =>
            ExecuteAsync(async () =>
            {
                var section = await _narrativeService.DraftAsync(request.AssessmentId, request.RiskCategoryId, request.RegenerationFeedback);
                return OperationResult<NarrativeSection>.Success(section);
            }, "Failed to draft narrative section.");

        public record ReviewRequest(Guid AssessmentId, Guid RiskCategoryId, Guid ActorUserId);

        /// <summary>US-6.3: accept an AI draft as-is - no reason required.</summary>
        [HttpPost("Review")]
        public Task<IActionResult> Review([FromBody] ReviewRequest request) =>
            ExecuteAsync(async () =>
            {
                var id = await _narrativeService.ReviewAsync(request.AssessmentId, request.RiskCategoryId, request.ActorUserId);
                return OperationResult<Guid>.Success(id);
            }, "Failed to review narrative section.");

        /// <summary>US-6.1: reason mandatory - enforced by func_editNarrativeSection.</summary>
        [HttpPost("Edit")]
        public Task<IActionResult> Edit([FromBody] EditNarrativeSectionInput input) =>
            ExecuteAsync(async () =>
            {
                try
                {
                    var id = await _narrativeService.EditAsync(input);
                    return OperationResult<Guid>.Success(id);
                }
                catch (Exception ex) when (ex.Message.Contains("reason is required", StringComparison.OrdinalIgnoreCase))
                {
                    return OperationResult<Guid>.BadRequest(ex.Message);
                }
            }, "Failed to edit narrative section.");

        [HttpGet("{assessmentId:guid}")]
        public Task<IActionResult> GetSections(Guid assessmentId) =>
            ExecuteAsync(async () =>
            {
                var sections = await _narrativeService.GetSectionsAsync(assessmentId);
                return OperationResult<IReadOnlyList<NarrativeSection>>.Success(sections);
            }, "Failed to fetch narrative sections.");
    }
}
