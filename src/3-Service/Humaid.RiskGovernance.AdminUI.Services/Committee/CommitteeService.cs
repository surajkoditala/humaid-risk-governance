namespace Humaid.RiskGovernance.AdminUI.Services.Committee
{
    using System.Text.Json;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Assessment;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.ChangeRequests;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Committee;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Configuration;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Audit;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Committee;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.DataIngestion;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Audit;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Committee;
    using Microsoft.Extensions.Logging;

    /// <summary>Epic 8. The committee decision resolution rule (quorum + conservative
    /// reject/defer-wins policy) is documented in docs/architecture/architecture-mapping.md -
    /// this class is the one place that rule is implemented.</summary>
    public class CommitteeService : ICommitteeService
    {
        private const string CommitteeQuorumRuleKey = "CommitteeQuorum";

        private readonly ICommitteeRepo _committeeRepo;
        private readonly IWorkflowRuleRepo _workflowRuleRepo;
        private readonly IAssessmentRepo _assessmentRepo;
        private readonly IChangeRequestRepo _changeRequestRepo;
        private readonly IDataIngestionService _dataIngestionService;
        private readonly IMockSystemsClient _mockSystemsClient;
        private readonly IAuditService _auditService;
        private readonly ILogger<CommitteeService> _logger;

        public CommitteeService(
            ICommitteeRepo committeeRepo,
            IWorkflowRuleRepo workflowRuleRepo,
            IAssessmentRepo assessmentRepo,
            IChangeRequestRepo changeRequestRepo,
            IDataIngestionService dataIngestionService,
            IMockSystemsClient mockSystemsClient,
            IAuditService auditService,
            ILogger<CommitteeService> logger)
        {
            _committeeRepo = committeeRepo;
            _workflowRuleRepo = workflowRuleRepo;
            _assessmentRepo = assessmentRepo;
            _changeRequestRepo = changeRequestRepo;
            _dataIngestionService = dataIngestionService;
            _mockSystemsClient = mockSystemsClient;
            _auditService = auditService;
            _logger = logger;
        }

        public Task RouteToCommitteeAsync(Guid assessmentId, Guid actorUserId) => _committeeRepo.RouteAsync(assessmentId, actorUserId);

        public Task<IReadOnlyList<CommitteeQueueItem>> GetQueueAsync() => _committeeRepo.GetQueueAsync();

        public async Task<Guid> CastVoteAsync(CastCommitteeVoteInput input)
        {
            var assessment = await _assessmentRepo.GetByIdAsync(input.AssessmentId)
                ?? throw new InvalidOperationException($"Assessment {input.AssessmentId} not found.");
            var changeRequest = await _changeRequestRepo.GetByIdAsync(assessment.ChangeRequestId)
                ?? throw new InvalidOperationException($"Change request {assessment.ChangeRequestId} not found.");

            // US-8.2 is scoped to items already in the committee's queue - voting on something not
            // yet routed (US-8.1) would record a vote nobody asked for.
            if (changeRequest.Status != "PendingCommittee")
            {
                throw new InvalidOperationException(
                    $"Assessment {input.AssessmentId} is not in the committee queue (change request status: {changeRequest.Status}). Route it first.");
            }

            var voteId = await _committeeRepo.CastVoteAsync(input);
            await TryResolveDecisionAsync(input.AssessmentId);
            return voteId;
        }

        public Task<IReadOnlyList<CommitteeVote>> GetVotesAsync(Guid assessmentId) => _committeeRepo.GetVotesAsync(assessmentId);

        public Task<CommitteeDecision?> GetDecisionAsync(Guid assessmentId) => _committeeRepo.GetDecisionAsync(assessmentId);

        private async Task TryResolveDecisionAsync(Guid assessmentId)
        {
            if (await _committeeRepo.GetDecisionAsync(assessmentId) is not null)
            {
                return; // already decided - votes cast after resolution don't re-trigger it.
            }

            var quorumRule = await _workflowRuleRepo.GetActiveAsync(CommitteeQuorumRuleKey);
            if (quorumRule is null)
            {
                return; // no quorum configured - don't guess; an Admin must set one (US-10.2).
            }

            // A malformed/missing "quorum" key is treated the same as "not configured" (don't
            // guess, don't crash) rather than throwing on a config value an Admin got wrong.
            if (!JsonDocument.Parse(quorumRule.RuleValueJson).RootElement.TryGetProperty("quorum", out var quorumElement)
                || !quorumElement.TryGetInt32(out var quorum))
            {
                return;
            }
            var votes = await _committeeRepo.GetVotesAsync(assessmentId);
            if (votes.Count < quorum)
            {
                return;
            }

            // Resolution rule (documented in docs/architecture/architecture-mapping.md):
            // 1. Any Reject -> Rejected. 2. Else any Defer -> Deferred.
            // 3. Else any ApproveWithConditions -> ApprovedWithConditions (conditions merged).
            // 4. Else (all Approve) -> Approved.
            string resolution;
            string? conditionsText = null;

            if (votes.Any(v => v.Vote == "Reject"))
            {
                resolution = "Rejected";
            }
            else if (votes.Any(v => v.Vote == "Defer"))
            {
                resolution = "Deferred";
            }
            else if (votes.Any(v => v.Vote == "ApproveWithConditions"))
            {
                resolution = "ApprovedWithConditions";
                conditionsText = string.Join(
                    " | ",
                    votes.Where(v => v.Vote == "ApproveWithConditions" && !string.IsNullOrWhiteSpace(v.ConditionsText))
                         .Select(v => $"{v.CommitteeMemberName}: {v.ConditionsText}"));
            }
            else
            {
                resolution = "Approved";
            }

            await _committeeRepo.RecordDecisionAsync(assessmentId, resolution, conditionsText);

            // Phase 3 Step 5 - the feedback loop the architect's ecosystem doc diagrams: a
            // decision that already happened shouldn't need a human to re-key it into the
            // originating system (go-live flag -> Core Banking, updated risk rating -> Vendor
            // Mgmt, risk flag -> CRM). Only fires for whichever entity the change request was
            // actually linked to at intake (Step 3) - most change types link at most one.
            var assessment = await _assessmentRepo.GetByIdAsync(assessmentId);
            if (assessment is not null)
            {
                await PushDecisionToMockSystemsAsync(assessment.ChangeRequestId, resolution, conditionsText);
            }
        }

        private async Task PushDecisionToMockSystemsAsync(Guid changeRequestId, string resolution, string? conditionsText)
        {
            var snapshot = await _dataIngestionService.GetSnapshotAsync(changeRequestId);
            if (snapshot is null) return; // change type had no linked Mock Systems entity at intake.

            var goLive = resolution is "Approved" or "ApprovedWithConditions";
            var ratingSummary = resolution switch
            {
                "Approved" => "Low - approved without conditions",
                "ApprovedWithConditions" => $"Approved with conditions: {conditionsText}",
                "Deferred" => "Deferred - pending further committee review",
                "Rejected" => "Rejected - not approved",
                _ => resolution,
            };

            try
            {
                if (snapshot.MockProductId is Guid productId)
                {
                    await _mockSystemsClient.PushProductRiskFlagAsync(productId, goLive, ratingSummary);
                }
                if (snapshot.MockVendorId is Guid vendorId)
                {
                    await _mockSystemsClient.PushVendorRiskFlagAsync(vendorId, ratingSummary);
                }
                if (snapshot.MockCustomerId is Guid customerId)
                {
                    await _mockSystemsClient.PushCustomerRiskFlagAsync(customerId, ratingSummary);
                }
            }
            catch (HttpRequestException ex)
            {
                // Best-effort by design, same reasoning as DataIngestionService.IngestAsync - Mock
                // Systems being unreachable must not undo or block a decision that's already final.
                _logger.LogWarning(ex, "Could not push committee decision for change request {ChangeRequestId} back to Mock Systems.", changeRequestId);
                return;
            }

            // Per the architect's doc: never a silent update - this push is itself an audit event,
            // logged only once it actually succeeded above.
            await _auditService.LogAsync(new AppendAuditEventInput
            {
                ChangeRequestId = changeRequestId,
                EntityType = "MockSystemsFeedback",
                EntityId = changeRequestId,
                Action = "Pushed",
                ActorLabel = "system",
                AfterValueJson = JsonSerializer.Serialize(new { resolution, goLive, ratingSummary }),
            });
        }
    }
}
