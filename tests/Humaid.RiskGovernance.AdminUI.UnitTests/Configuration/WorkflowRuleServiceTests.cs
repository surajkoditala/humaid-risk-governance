namespace Humaid.RiskGovernance.AdminUI.UnitTests.Configuration
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Configuration;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Users;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Configuration;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core;
    using Humaid.RiskGovernance.AdminUI.Services.Configuration;
    using Moq;
    using Xunit;

    /// <summary>US-10.2's "Analyst with configuration privileges" role guard (DEF-002) and
    /// mandatory reason (AC2).</summary>
    public class WorkflowRuleServiceTests
    {
        private readonly Mock<IWorkflowRuleRepo> _repo = new();
        private readonly Mock<IUserRepo> _userRepo = new();
        private readonly WorkflowRuleService _sut;

        public WorkflowRuleServiceTests()
        {
            SetUpActorRole("Analyst");
            _sut = new WorkflowRuleService(_repo.Object, _userRepo.Object);
        }

        /// <summary>A user can hold more than one role (Epic 11 follow-up), so HasRoleAsync is a
        /// membership check, not equality - this mocks "the actor's only role is <paramref
        /// name="role"/>" for tests that only care about a single one.</summary>
        private void SetUpActorRole(string role) =>
            _userRepo.Setup(u => u.HasRoleAsync(It.IsAny<Guid>(), It.IsAny<string>()))
                .ReturnsAsync((Guid _, string checkedRole) => checkedRole == role);

        private static UpsertWorkflowRuleInput ValidInput() => new()
        {
            RuleKey = "CommitteeQuorum",
            RuleValueJson = "{\"quorum\": 2}",
            Reason = "Initial default",
            ActorUserId = Guid.NewGuid(),
        };

        [Theory]
        [InlineData("ProductOwner")]
        [InlineData("CommitteeMember")]
        public async Task UpsertAsync_RejectsActorWithoutConfigurationPrivileges(string role)
        {
            SetUpActorRole(role);

            await Assert.ThrowsAsync<ValidationException>(() => _sut.UpsertAsync(ValidInput()));
            _repo.Verify(r => r.UpsertAsync(It.IsAny<UpsertWorkflowRuleInput>()), Times.Never);
        }

        [Fact]
        public async Task UpsertAsync_RejectsBlankReason()
        {
            var input = ValidInput();
            input.Reason = "   ";

            await Assert.ThrowsAsync<ValidationException>(() => _sut.UpsertAsync(input));
            _repo.Verify(r => r.UpsertAsync(It.IsAny<UpsertWorkflowRuleInput>()), Times.Never);
        }

        [Fact]
        public async Task UpsertAsync_AllowsAnalystWithAReason()
        {
            var id = Guid.NewGuid();
            _repo.Setup(r => r.UpsertAsync(It.IsAny<UpsertWorkflowRuleInput>())).ReturnsAsync(id);

            var result = await _sut.UpsertAsync(ValidInput());

            Assert.Equal(id, result);
        }
    }
}
