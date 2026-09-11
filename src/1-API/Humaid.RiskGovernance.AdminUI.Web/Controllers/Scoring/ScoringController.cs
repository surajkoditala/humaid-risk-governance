namespace Humaid.RiskGovernance.AdminUI.Web.Controllers.Scoring
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Scoring;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Scoring;
    using Humaid.RiskGovernance.AdminUI.Web.Controllers.Core;
    using Microsoft.AspNetCore.Authorization;
    using Microsoft.AspNetCore.Mvc;

    /// <summary>Epic 7 - Risk Scoring Engine. Deterministic - no LLM anywhere in this controller
    /// or the services/functions it calls.</summary>
    [Authorize]
    [Route("api/[controller]")]
    public class ScoringController : BaseApiController
    {
        private readonly IScoringService _scoringService;

        public ScoringController(IScoringService scoringService, ILogger<ScoringController> logger)
            : base(logger)
        {
            _scoringService = scoringService;
        }

        /// <summary>US-10.1: rejects any config that would let residual risk reach zero.</summary>
        [HttpPost("Config")]
        public Task<IActionResult> UpsertConfig([FromBody] UpsertScoringConfigInput input) =>
            ExecuteAsync(async () =>
            {
                try
                {
                    var id = await _scoringService.UpsertConfigAsync(input);
                    return OperationResult<Guid>.Success(id);
                }
                catch (InvalidOperationException ex)
                {
                    return OperationResult<Guid>.BadRequest(ex.Message);
                }
            }, "Failed to update scoring configuration.");

        /// <summary>US-7.1: Residual = Inherent - (Effectiveness x Mitigation), residual always > 0.</summary>
        [HttpPost("Calculate")]
        public Task<IActionResult> Calculate([FromBody] CalculateRiskScoreInput input) =>
            ExecuteAsync(async () =>
            {
                var score = await _scoringService.CalculateAsync(input);
                return OperationResult<RiskScore>.Success(score);
            }, "Failed to calculate risk score.");

        /// <summary>US-7.2: reason mandatory; rejects any value &lt;= 0.</summary>
        [HttpPost("Override")]
        public Task<IActionResult> Override([FromBody] OverrideRiskScoreInput input) =>
            ExecuteAsync(async () =>
            {
                try
                {
                    var id = await _scoringService.OverrideAsync(input);
                    return OperationResult<Guid>.Success(id);
                }
                catch (InvalidOperationException ex)
                {
                    return OperationResult<Guid>.BadRequest(ex.Message);
                }
            }, "Failed to override risk score.");

        [HttpGet("{assessmentId:guid}")]
        public Task<IActionResult> GetScores(Guid assessmentId) =>
            ExecuteAsync(async () =>
            {
                var scores = await _scoringService.GetScoresAsync(assessmentId);
                return OperationResult<IReadOnlyList<RiskScore>>.Success(scores);
            }, "Failed to fetch risk scores.");

        [HttpGet("Controls/{riskCategoryId:guid}")]
        public Task<IActionResult> GetControls(Guid riskCategoryId) =>
            ExecuteAsync(async () =>
            {
                var controls = await _scoringService.GetControlsAsync(riskCategoryId);
                return OperationResult<IReadOnlyList<Control>>.Success(controls);
            }, "Failed to fetch controls.");
    }
}
