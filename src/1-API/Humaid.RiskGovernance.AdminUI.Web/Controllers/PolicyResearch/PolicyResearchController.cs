namespace Humaid.RiskGovernance.AdminUI.Web.Controllers.PolicyResearch
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.PolicyResearch;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.PolicyResearch;
    using Humaid.RiskGovernance.AdminUI.Web.Controllers.Core;
    using Microsoft.AspNetCore.Authorization;
    using Microsoft.AspNetCore.Mvc;

    /// <summary>Epic 3 - AI-Assisted Policy Research. Search is deterministic full-text search,
    /// not an LLM call - see docs/governance/human-in-the-loop-gates.md.</summary>
    [Authorize]
    [Route("api/[controller]")]
    public class PolicyResearchController : BaseApiController
    {
        private readonly IPolicyResearchService _policyResearchService;

        public PolicyResearchController(IPolicyResearchService policyResearchService, ILogger<PolicyResearchController> logger)
            : base(logger)
        {
            _policyResearchService = policyResearchService;
        }

        [HttpGet("Search")]
        public Task<IActionResult> Search([FromQuery] string queryText, [FromQuery] Guid? riskCategoryId, [FromQuery] int topK = 5) =>
            ExecuteAsync(async () =>
            {
                var results = await _policyResearchService.SearchAsync(queryText, riskCategoryId, topK);
                return OperationResult<IReadOnlyList<PolicyChunkSearchResult>>.Success(results);
            }, "Failed to search policy corpus.");

        [HttpPost("RecordReliance")]
        public Task<IActionResult> RecordReliance([FromBody] RecordPolicyRelianceInput input) =>
            ExecuteAsync(async () =>
            {
                var id = await _policyResearchService.RecordRelianceAsync(input);
                return OperationResult<Guid>.Success(id);
            }, "Failed to record policy reliance.");

        [HttpGet("{assessmentId:guid}/Reliance")]
        public Task<IActionResult> GetReliance(Guid assessmentId) =>
            ExecuteAsync(async () =>
            {
                var reliance = await _policyResearchService.GetRelianceAsync(assessmentId);
                return OperationResult<IReadOnlyList<PolicyReliance>>.Success(reliance);
            }, "Failed to fetch policy reliance.");
    }
}
