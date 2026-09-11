namespace Humaid.RiskGovernance.AdminUI.UnitTests.Committee
{
    using System.Net;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Assessment;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.ChangeRequests;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Committee;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Configuration;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Audit;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.DataIngestion;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Audit;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.ChangeRequests;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Committee;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Configuration;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.DataIngestion;
    using Humaid.RiskGovernance.AdminUI.Services.Committee;
    using Microsoft.Extensions.Logging.Abstractions;
    using Moq;
    using Xunit;

    /// <summary>
    /// The quorum-based resolution rule (docs/architecture/architecture-mapping.md) and Phase 3's
    /// feedback-loop addition to it - both exercised through CastVoteAsync exactly as the
    /// controller calls it, not by reaching into the private resolution method directly.
    /// </summary>
    public class CommitteeServiceTests
    {
        private readonly Mock<ICommitteeRepo> _committeeRepo = new();
        private readonly Mock<IWorkflowRuleRepo> _workflowRuleRepo = new();
        private readonly Mock<IAssessmentRepo> _assessmentRepo = new();
        private readonly Mock<IChangeRequestRepo> _changeRequestRepo = new();
        private readonly Mock<IDataIngestionService> _dataIngestionService = new();
        private readonly Mock<IMockSystemsClient> _mockSystemsClient = new();
        private readonly Mock<IAuditService> _auditService = new();
        private readonly CommitteeService _sut;

        private readonly Guid _assessmentId = Guid.NewGuid();
        private readonly Guid _changeRequestId = Guid.NewGuid();

        public CommitteeServiceTests()
        {
            _sut = new CommitteeService(
                _committeeRepo.Object, _workflowRuleRepo.Object, _assessmentRepo.Object, _changeRequestRepo.Object,
                _dataIngestionService.Object, _mockSystemsClient.Object, _auditService.Object,
                NullLogger<CommitteeService>.Instance);

            _assessmentRepo.Setup(r => r.GetByIdAsync(_assessmentId))
                .ReturnsAsync(new Infrastructure.Models.Assessment.Assessment { Id = _assessmentId, ChangeRequestId = _changeRequestId, Status = "Finalized" });
            _changeRequestRepo.Setup(r => r.GetByIdAsync(_changeRequestId))
                .ReturnsAsync(new ChangeRequest { Id = _changeRequestId, Status = "PendingCommittee" });
            _committeeRepo.Setup(r => r.GetDecisionAsync(_assessmentId)).ReturnsAsync((CommitteeDecision?)null);
            _workflowRuleRepo.Setup(r => r.GetActiveAsync("CommitteeQuorum"))
                .ReturnsAsync(new WorkflowRule { RuleKey = "CommitteeQuorum", RuleValueJson = """{"quorum": 2}""", IsActive = true });
            _committeeRepo.Setup(r => r.CastVoteAsync(It.IsAny<CastCommitteeVoteInput>())).ReturnsAsync(Guid.NewGuid());
            // No linked Mock Systems entity by default - individual tests override this to exercise the feedback loop.
            _dataIngestionService.Setup(s => s.GetSnapshotAsync(_changeRequestId, default)).ReturnsAsync((ExternalSnapshot?)null);
        }

        [Fact]
        public async Task CastVoteAsync_RejectsVoteWhenNotYetRoutedToCommittee()
        {
            _changeRequestRepo.Setup(r => r.GetByIdAsync(_changeRequestId))
                .ReturnsAsync(new ChangeRequest { Id = _changeRequestId, Status = "InAssessment" });

            var input = new CastCommitteeVoteInput { AssessmentId = _assessmentId, CommitteeMemberUserId = Guid.NewGuid(), Vote = "Approve" };

            await Assert.ThrowsAsync<InvalidOperationException>(() => _sut.CastVoteAsync(input));
            _committeeRepo.Verify(r => r.CastVoteAsync(It.IsAny<CastCommitteeVoteInput>()), Times.Never);
        }

        [Fact]
        public async Task CastVoteAsync_DoesNotResolveBelowQuorum()
        {
            _committeeRepo.Setup(r => r.GetVotesAsync(_assessmentId))
                .ReturnsAsync([Vote("Approve")]); // 1 vote, quorum is 2

            await _sut.CastVoteAsync(new CastCommitteeVoteInput { AssessmentId = _assessmentId, CommitteeMemberUserId = Guid.NewGuid(), Vote = "Approve" });

            _committeeRepo.Verify(r => r.RecordDecisionAsync(It.IsAny<Guid>(), It.IsAny<string>(), It.IsAny<string?>()), Times.Never);
        }

        [Theory]
        [MemberData(nameof(ResolutionCases))]
        public async Task CastVoteAsync_ResolvesPerTheConservativeWinsRule(string[] votes, string expectedResolution)
        {
            _committeeRepo.Setup(r => r.GetVotesAsync(_assessmentId)).ReturnsAsync(votes.Select(v => Vote(v)).ToList());

            await _sut.CastVoteAsync(new CastCommitteeVoteInput { AssessmentId = _assessmentId, CommitteeMemberUserId = Guid.NewGuid(), Vote = votes[^1] });

            _committeeRepo.Verify(r => r.RecordDecisionAsync(_assessmentId, expectedResolution, It.IsAny<string?>()), Times.Once);
        }

        public static IEnumerable<object[]> ResolutionCases =>
        [
            [new[] { "Approve", "Reject" }, "Rejected"],                       // Reject wins over everything
            [new[] { "Reject", "Defer" }, "Rejected"],                         // ...even over Defer
            [new[] { "Approve", "Defer" }, "Deferred"],                        // Defer wins over Approve
            [new[] { "ApproveWithConditions", "Defer" }, "Deferred"],          // ...and over ApproveWithConditions
            [new[] { "Approve", "ApproveWithConditions" }, "ApprovedWithConditions"],
            [new[] { "Approve", "Approve" }, "Approved"],                      // unanimous Approve, nothing else
        ];

        [Fact]
        public async Task CastVoteAsync_MergesConditionsTextFromEveryApproveWithConditionsVote()
        {
            var votes = new List<CommitteeVote>
            {
                Vote("ApproveWithConditions", conditionsText: "Quarterly AML re-review", memberName: "Jordan Blake"),
                Vote("ApproveWithConditions", conditionsText: "Limit to $250k/day", memberName: "Riley Voss"),
            };
            _committeeRepo.Setup(r => r.GetVotesAsync(_assessmentId)).ReturnsAsync(votes);

            await _sut.CastVoteAsync(new CastCommitteeVoteInput { AssessmentId = _assessmentId, CommitteeMemberUserId = Guid.NewGuid(), Vote = "ApproveWithConditions" });

            _committeeRepo.Verify(r => r.RecordDecisionAsync(
                _assessmentId, "ApprovedWithConditions",
                It.Is<string>(c => c!.Contains("Quarterly AML re-review") && c.Contains("Limit to $250k/day"))), Times.Once);
        }

        [Fact]
        public async Task CastVoteAsync_DoesNotReResolveAnAlreadyDecidedAssessment()
        {
            _committeeRepo.Setup(r => r.GetDecisionAsync(_assessmentId))
                .ReturnsAsync(new CommitteeDecision { Id = Guid.NewGuid(), Resolution = "Approved" });

            await _sut.CastVoteAsync(new CastCommitteeVoteInput { AssessmentId = _assessmentId, CommitteeMemberUserId = Guid.NewGuid(), Vote = "Reject" });

            _committeeRepo.Verify(r => r.RecordDecisionAsync(It.IsAny<Guid>(), It.IsAny<string>(), It.IsAny<string?>()), Times.Never);
        }

        // ---- Phase 3 Step 5: feedback loop -------------------------------------------------------

        [Fact]
        public async Task CastVoteAsync_PushesGoLiveTrueToMockProductWhenApproved()
        {
            _committeeRepo.Setup(r => r.GetVotesAsync(_assessmentId)).ReturnsAsync([Vote("Approve"), Vote("Approve")]);
            var productId = Guid.NewGuid();
            _dataIngestionService.Setup(s => s.GetSnapshotAsync(_changeRequestId, default))
                .ReturnsAsync(new ExternalSnapshot { ChangeRequestId = _changeRequestId, MockProductId = productId });

            await _sut.CastVoteAsync(new CastCommitteeVoteInput { AssessmentId = _assessmentId, CommitteeMemberUserId = Guid.NewGuid(), Vote = "Approve" });

            _mockSystemsClient.Verify(c => c.PushProductRiskFlagAsync(productId, true, It.IsAny<string>(), default), Times.Once);
            _auditService.Verify(a => a.LogAsync(It.Is<AppendAuditEventInput>(e => e.EntityType == "MockSystemsFeedback")), Times.Once);
        }

        [Fact]
        public async Task CastVoteAsync_PushesGoLiveFalseToMockProductWhenRejected()
        {
            _committeeRepo.Setup(r => r.GetVotesAsync(_assessmentId)).ReturnsAsync([Vote("Reject"), Vote("Approve")]);
            var productId = Guid.NewGuid();
            _dataIngestionService.Setup(s => s.GetSnapshotAsync(_changeRequestId, default))
                .ReturnsAsync(new ExternalSnapshot { ChangeRequestId = _changeRequestId, MockProductId = productId });

            await _sut.CastVoteAsync(new CastCommitteeVoteInput { AssessmentId = _assessmentId, CommitteeMemberUserId = Guid.NewGuid(), Vote = "Reject" });

            _mockSystemsClient.Verify(c => c.PushProductRiskFlagAsync(productId, false, It.IsAny<string>(), default), Times.Once);
        }

        [Fact]
        public async Task CastVoteAsync_SkipsFeedbackPushWhenNoEntityWasLinkedAtIntake()
        {
            _committeeRepo.Setup(r => r.GetVotesAsync(_assessmentId)).ReturnsAsync([Vote("Approve"), Vote("Approve")]);
            // default setup: GetSnapshotAsync returns null (no linked entity)

            await _sut.CastVoteAsync(new CastCommitteeVoteInput { AssessmentId = _assessmentId, CommitteeMemberUserId = Guid.NewGuid(), Vote = "Approve" });

            _mockSystemsClient.Verify(c => c.PushProductRiskFlagAsync(It.IsAny<Guid>(), It.IsAny<bool>(), It.IsAny<string>(), default), Times.Never);
            _mockSystemsClient.Verify(c => c.PushVendorRiskFlagAsync(It.IsAny<Guid>(), It.IsAny<string>(), default), Times.Never);
            _mockSystemsClient.Verify(c => c.PushCustomerRiskFlagAsync(It.IsAny<Guid>(), It.IsAny<string>(), default), Times.Never);
            _auditService.Verify(a => a.LogAsync(It.IsAny<AppendAuditEventInput>()), Times.Never);
        }

        [Fact]
        public async Task CastVoteAsync_SwallowsMockSystemsOutageRatherThanFailingTheVote()
        {
            _committeeRepo.Setup(r => r.GetVotesAsync(_assessmentId)).ReturnsAsync([Vote("Approve"), Vote("Approve")]);
            var vendorId = Guid.NewGuid();
            _dataIngestionService.Setup(s => s.GetSnapshotAsync(_changeRequestId, default))
                .ReturnsAsync(new ExternalSnapshot { ChangeRequestId = _changeRequestId, MockVendorId = vendorId });
            _mockSystemsClient.Setup(c => c.PushVendorRiskFlagAsync(vendorId, It.IsAny<string>(), default))
                .ThrowsAsync(new HttpRequestException("connection refused", null, HttpStatusCode.ServiceUnavailable));

            // Must not throw - the decision itself already stands; Mock Systems being down is a
            // best-effort push, same reasoning as DataIngestionService.IngestAsync.
            await _sut.CastVoteAsync(new CastCommitteeVoteInput { AssessmentId = _assessmentId, CommitteeMemberUserId = Guid.NewGuid(), Vote = "Approve" });

            _committeeRepo.Verify(r => r.RecordDecisionAsync(_assessmentId, "Approved", It.IsAny<string?>()), Times.Once);
            _auditService.Verify(a => a.LogAsync(It.IsAny<AppendAuditEventInput>()), Times.Never); // never a silent/false "it worked" log
        }

        private static CommitteeVote Vote(string vote, string? conditionsText = null, string memberName = "Committee Member") => new()
        {
            Id = Guid.NewGuid(),
            CommitteeMemberUserId = Guid.NewGuid(),
            CommitteeMemberName = memberName,
            Vote = vote,
            ConditionsText = conditionsText,
        };
    }
}
