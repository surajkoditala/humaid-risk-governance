namespace Humaid.RiskGovernance.AdminUI.Web.Controllers.Committee
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Committee;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Committee;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core;
    using Humaid.RiskGovernance.AdminUI.Web.Controllers.Core;
    using Microsoft.AspNetCore.Authorization;
    using Microsoft.AspNetCore.Mvc;

    /// <summary>Epic 8 - Committee Review &amp; Voting.</summary>
    [Authorize]
    [Route("api/[controller]")]
    public class CommitteeController : BaseApiController
    {
        private readonly ICommitteeService _committeeService;

        public CommitteeController(ICommitteeService committeeService, ILogger<CommitteeController> logger)
            : base(logger)
        {
            _committeeService = committeeService;
        }

        public record RouteRequest(Guid AssessmentId, Guid ActorUserId);

        /// <summary>US-8.1: assessment must already be Finalized (func_routeToCommittee enforces this).</summary>
        [HttpPost("Route")]
        public Task<IActionResult> Route([FromBody] RouteRequest request) =>
            ExecuteAsync(async () =>
            {
                try
                {
                    await _committeeService.RouteToCommitteeAsync(request.AssessmentId, request.ActorUserId);
                    return OperationResult<string>.Success("Routed");
                }
                catch (Exception ex) when (ex.Message.Contains("must be Finalized", StringComparison.OrdinalIgnoreCase))
                {
                    return OperationResult<string>.BadRequest(ex.Message);
                }
            }, "Failed to route assessment to committee.");

        [HttpGet("Queue")]
        public Task<IActionResult> GetQueue() =>
            ExecuteAsync(async () =>
            {
                var queue = await _committeeService.GetQueueAsync();
                return OperationResult<IReadOnlyList<CommitteeQueueItem>>.Success(queue);
            }, "Failed to fetch committee queue.");

        /// <summary>US-8.2: approve-with-conditions/reject/defer text requirements are enforced by
        /// committee_vote's own CHECK constraints.</summary>
        [HttpPost("Vote")]
        public Task<IActionResult> Vote([FromBody] CastCommitteeVoteInput input) =>
            ExecuteAsync(async () =>
            {
                try
                {
                    var id = await _committeeService.CastVoteAsync(input);
                    return OperationResult<Guid>.Success(id);
                }
                catch (Exception ex) when (ex.Message.Contains("violates check constraint", StringComparison.OrdinalIgnoreCase))
                {
                    return OperationResult<Guid>.BadRequest(
                        "Approve-with-conditions requires conditions text; reject/defer require a rationale.");
                }
                catch (InvalidOperationException ex)
                {
                    return OperationResult<Guid>.BadRequest(ex.Message);
                }
            }, "Failed to cast committee vote.");

        [HttpGet("{assessmentId:guid}/Votes")]
        public Task<IActionResult> GetVotes(Guid assessmentId) =>
            ExecuteAsync(async () =>
            {
                var votes = await _committeeService.GetVotesAsync(assessmentId);
                return OperationResult<IReadOnlyList<CommitteeVote>>.Success(votes);
            }, "Failed to fetch committee votes.");

        /// <summary>US-8.3: resolved automatically once quorum is met (see CastVote); this just
        /// reads the outcome, if any, for the Product Owner / audit view.</summary>
        [HttpGet("{assessmentId:guid}/Decision")]
        public Task<IActionResult> GetDecision(Guid assessmentId) =>
            ExecuteAsync(async () =>
            {
                var decision = await _committeeService.GetDecisionAsync(assessmentId);
                return decision is null
                    ? OperationResult<CommitteeDecision>.NotFound("No decision recorded yet.")
                    : OperationResult<CommitteeDecision>.Success(decision);
            }, "Failed to fetch committee decision.");
    }
}
