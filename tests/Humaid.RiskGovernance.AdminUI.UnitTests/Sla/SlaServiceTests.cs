namespace Humaid.RiskGovernance.AdminUI.UnitTests.Sla
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Sla;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Users;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Sla;
    using Humaid.RiskGovernance.AdminUI.Services.Sla;
    using Moq;
    using Xunit;

    /// <summary>Epic 19: US-19.1's Admin-only guard, mandatory reason, refusal of bad targets (nothing
    /// written), and the "stage targets exceed end-to-end" warning that must be confirmed. The SLA
    /// arithmetic itself lives in SQL and is covered by the database-level tests in the PR notes.</summary>
    public class SlaServiceTests
    {
        private static readonly string[] ChangeTypes = ["Product", "Feature", "Process", "Vendor", "Geography", "CustomerSegment"];

        private readonly Mock<ISlaRepo> _repo = new();
        private readonly Mock<IUserRepo> _userRepo = new();
        private readonly SlaService _sut;

        public SlaServiceTests()
        {
            _userRepo.Setup(u => u.GetRoleAsync(It.IsAny<Guid>())).ReturnsAsync("Admin");
            _repo.Setup(r => r.UpsertConfigAsync(It.IsAny<string>(), It.IsAny<SaveSlaConfigInput>())).ReturnsAsync(Guid.NewGuid());
            _sut = new SlaService(_repo.Object, _userRepo.Object);
        }

        /// <summary>The confirmed defaults: 2 / 8 / 5 business days per stage, 15 end to end.</summary>
        private static List<SlaTarget> DefaultTargets() =>
            ChangeTypes.SelectMany(type => new[]
            {
                new SlaTarget { ChangeType = type, Stage = SlaStages.Submitted, TargetBusinessDays = 2 },
                new SlaTarget { ChangeType = type, Stage = SlaStages.InAssessment, TargetBusinessDays = 8 },
                new SlaTarget { ChangeType = type, Stage = SlaStages.PendingCommittee, TargetBusinessDays = 5 },
                new SlaTarget { ChangeType = type, Stage = SlaStages.EndToEnd, TargetBusinessDays = 15 },
            }).ToList();

        private static SaveSlaConfigInput ValidInput() => new()
        {
            Targets = DefaultTargets(),
            AtRiskThresholdPct = 80,
            PauseOnClarification = true,
            Reason = "Tune to current policy",
            ActorUserId = Guid.NewGuid(),
        };

        private void VerifyNothingWritten() =>
            _repo.Verify(r => r.UpsertConfigAsync(It.IsAny<string>(), It.IsAny<SaveSlaConfigInput>()), Times.Never);

        [Theory]
        [InlineData("Analyst")]
        [InlineData("ProductOwner")]
        [InlineData("CommitteeMember")]
        public async Task SaveConfigAsync_RefusesAnyoneWhoIsNotAdmin(string role)
        {
            _userRepo.Setup(u => u.GetRoleAsync(It.IsAny<Guid>())).ReturnsAsync(role);

            await Assert.ThrowsAsync<ValidationException>(() => _sut.SaveConfigAsync(ValidInput()));
            VerifyNothingWritten();
        }

        [Fact]
        public async Task SaveConfigAsync_RefusesAnUnknownActor()
        {
            _userRepo.Setup(u => u.GetRoleAsync(It.IsAny<Guid>())).ReturnsAsync((string?)null);

            await Assert.ThrowsAsync<ValidationException>(() => _sut.SaveConfigAsync(ValidInput()));
            VerifyNothingWritten();
        }

        [Theory]
        [InlineData("")]
        [InlineData("   ")]
        public async Task SaveConfigAsync_RequiresAReason(string reason)
        {
            var input = ValidInput();
            input.Reason = reason;

            await Assert.ThrowsAsync<ValidationException>(() => _sut.SaveConfigAsync(input));
            VerifyNothingWritten();
        }

        [Theory]
        [InlineData(0)]
        [InlineData(-5)]
        public async Task SaveConfigAsync_RefusesAZeroOrNegativeTarget(int days)
        {
            var input = ValidInput();
            input.Targets[0].TargetBusinessDays = days;

            var ex = await Assert.ThrowsAsync<ValidationException>(() => _sut.SaveConfigAsync(input));

            Assert.Contains("greater than zero", ex.Message);
            Assert.Contains(input.Targets[0].ChangeType, ex.Message); // names the entry that is wrong
            VerifyNothingWritten();
        }

        [Theory]
        [InlineData(0)]
        [InlineData(100)]
        [InlineData(-1)]
        public async Task SaveConfigAsync_RefusesAWarningThresholdOutsideOneToNinetyNine(int pct)
        {
            var input = ValidInput();
            input.AtRiskThresholdPct = pct;

            await Assert.ThrowsAsync<ValidationException>(() => _sut.SaveConfigAsync(input));
            VerifyNothingWritten();
        }

        [Fact]
        public async Task SaveConfigAsync_RefusesAnIncompleteTargetList()
        {
            var input = ValidInput();
            input.Targets.RemoveAt(0);

            await Assert.ThrowsAsync<ValidationException>(() => _sut.SaveConfigAsync(input));
            VerifyNothingWritten();
        }

        [Fact]
        public async Task SaveConfigAsync_RefusesARepeatedTarget()
        {
            var input = ValidInput();
            input.Targets[1] = new SlaTarget
            {
                ChangeType = input.Targets[0].ChangeType,
                Stage = input.Targets[0].Stage,
                TargetBusinessDays = 3,
            };

            await Assert.ThrowsAsync<ValidationException>(() => _sut.SaveConfigAsync(input));
            VerifyNothingWritten();
        }

        [Fact]
        public async Task SaveConfigAsync_SavesAConsistentConfiguration()
        {
            var result = await _sut.SaveConfigAsync(ValidInput());

            Assert.True(result.Saved);
            Assert.Empty(result.Warnings);
            _repo.Verify(r => r.UpsertConfigAsync(It.IsAny<string>(), It.IsAny<SaveSlaConfigInput>()), Times.Once);
        }

        [Fact]
        public async Task SaveConfigAsync_WarnsWithoutSavingWhenStageTargetsExceedEndToEnd()
        {
            var input = ValidInput();
            input.Targets.Single(t => t.ChangeType == "Vendor" && t.Stage == SlaStages.EndToEnd).TargetBusinessDays = 10; // 2 + 8 + 5 = 15 > 10

            var result = await _sut.SaveConfigAsync(input);

            Assert.False(result.Saved);
            var warning = Assert.Single(result.Warnings);
            Assert.Contains("Vendor", warning);
            VerifyNothingWritten();
        }

        [Fact]
        public async Task SaveConfigAsync_SavesTheInconsistentConfigurationOnceTheWarningIsConfirmed()
        {
            var input = ValidInput();
            input.Targets.Single(t => t.ChangeType == "Vendor" && t.Stage == SlaStages.EndToEnd).TargetBusinessDays = 10;
            input.ConfirmWarnings = true;

            var result = await _sut.SaveConfigAsync(input);

            Assert.True(result.Saved);
            Assert.NotEmpty(result.Warnings);
            _repo.Verify(r => r.UpsertConfigAsync(It.IsAny<string>(), It.IsAny<SaveSlaConfigInput>()), Times.Once);
        }

        [Fact]
        public async Task SaveConfigAsync_PassesTargetsToTheDatabaseAsCamelCaseJson()
        {
            string? sentJson = null;
            _repo.Setup(r => r.UpsertConfigAsync(It.IsAny<string>(), It.IsAny<SaveSlaConfigInput>()))
                .Callback<string, SaveSlaConfigInput>((json, _) => sentJson = json)
                .ReturnsAsync(Guid.NewGuid());

            await _sut.SaveConfigAsync(ValidInput());

            Assert.NotNull(sentJson);
            Assert.Contains("\"changeType\":\"Product\"", sentJson);
            Assert.Contains("\"targetBusinessDays\":2", sentJson);
        }

        [Theory]
        [InlineData("Analyst")]
        [InlineData("ProductOwner")]
        [InlineData("CommitteeMember")]
        public async Task AddHolidayAsync_RefusesAnyoneWhoIsNotAdmin(string role)
        {
            _userRepo.Setup(u => u.GetRoleAsync(It.IsAny<Guid>())).ReturnsAsync(role);

            await Assert.ThrowsAsync<ValidationException>(() =>
                _sut.AddHolidayAsync(new AddSlaHolidayInput { HolidayDate = "2026-12-25", Reason = "Bank holiday", ActorUserId = Guid.NewGuid() }));
            _repo.Verify(r => r.AddHolidayAsync(It.IsAny<AddSlaHolidayInput>()), Times.Never);
        }

        [Theory]
        [InlineData("not a date", "Bank holiday")]
        [InlineData("2026-13-45", "Bank holiday")]
        [InlineData("2026-12-25", " ")]
        public async Task AddHolidayAsync_RefusesABadDateOrABlankReason(string date, string reason)
        {
            await Assert.ThrowsAsync<ValidationException>(() =>
                _sut.AddHolidayAsync(new AddSlaHolidayInput { HolidayDate = date, Reason = reason, ActorUserId = Guid.NewGuid() }));
            _repo.Verify(r => r.AddHolidayAsync(It.IsAny<AddSlaHolidayInput>()), Times.Never);
        }

        [Fact]
        public async Task RemoveHolidayAsync_RequiresAReason()
        {
            await Assert.ThrowsAsync<ValidationException>(() =>
                _sut.RemoveHolidayAsync(Guid.NewGuid(), new RemoveSlaHolidayInput { Reason = "", ActorUserId = Guid.NewGuid() }));
            _repo.Verify(r => r.RemoveHolidayAsync(It.IsAny<Guid>(), It.IsAny<RemoveSlaHolidayInput>()), Times.Never);
        }

        [Theory]
        [InlineData("ProductOwner")]
        [InlineData("CommitteeMember")]
        public async Task SlaReporting_IsNotAvailableToProductOwnersOrCommitteeMembers(string role)
        {
            _userRepo.Setup(u => u.GetRoleAsync(It.IsAny<Guid>())).ReturnsAsync(role);
            var actor = Guid.NewGuid();

            await Assert.ThrowsAsync<ValidationException>(() => _sut.GetViewAsync(new SlaViewQuery { ActorUserId = actor }));
            await Assert.ThrowsAsync<ValidationException>(() => _sut.GetSummaryAsync(new SlaViewQuery { ActorUserId = actor }));
            await Assert.ThrowsAsync<ValidationException>(() => _sut.GetPerformanceAsync(actor, null));
            await Assert.ThrowsAsync<ValidationException>(() => _sut.GetRequestSlaAsync(actor, Guid.NewGuid()));
            _repo.Verify(r => r.GetViewAsync(It.IsAny<SlaViewQuery>()), Times.Never);
            _repo.Verify(r => r.GetSummaryAsync(It.IsAny<SlaViewQuery>()), Times.Never);
        }

        [Fact]
        public async Task GetViewAsync_TreatsBlankFiltersAsNoFilterAndKeepsPagingInRange()
        {
            _userRepo.Setup(u => u.GetRoleAsync(It.IsAny<Guid>())).ReturnsAsync("Analyst");
            SlaViewQuery? sent = null;
            _repo.Setup(r => r.GetViewAsync(It.IsAny<SlaViewQuery>()))
                .Callback<SlaViewQuery>(q => sent = q)
                .ReturnsAsync(new PagedResult<SlaViewRow>());

            await _sut.GetViewAsync(new SlaViewQuery
            {
                ActorUserId = Guid.NewGuid(),
                Stage = "",
                ChangeType = " ",
                State = null,
                Search = "  ",
                Page = 0,
                PageSize = 5000,
            });

            Assert.NotNull(sent);
            Assert.Null(sent!.Stage);
            Assert.Null(sent.ChangeType);
            Assert.Null(sent.Search);
            Assert.Equal(1, sent.Page);
            Assert.Equal(200, sent.PageSize);
        }

        [Fact]
        public async Task GetViewAsync_PassesRealFiltersSortAndPagingThrough()
        {
            _userRepo.Setup(u => u.GetRoleAsync(It.IsAny<Guid>())).ReturnsAsync("Admin");
            SlaViewQuery? sent = null;
            _repo.Setup(r => r.GetViewAsync(It.IsAny<SlaViewQuery>()))
                .Callback<SlaViewQuery>(q => sent = q)
                .ReturnsAsync(new PagedResult<SlaViewRow>());

            await _sut.GetViewAsync(new SlaViewQuery
            {
                ActorUserId = Guid.NewGuid(),
                Stage = "InAssessment",
                ChangeType = "Vendor",
                State = "Breached",
                Search = "payments",
                SortBy = "dueAt",
                SortDir = "desc",
                Page = 3,
                PageSize = 25,
            });

            Assert.NotNull(sent);
            Assert.Equal("InAssessment", sent!.Stage);
            Assert.Equal("Vendor", sent.ChangeType);
            Assert.Equal("Breached", sent.State);
            Assert.Equal("payments", sent.Search);
            Assert.Equal("dueAt", sent.SortBy);
            Assert.Equal("desc", sent.SortDir);
            Assert.Equal(3, sent.Page);
            Assert.Equal(25, sent.PageSize);
        }

        [Fact]
        public async Task GetSummaryAsync_ReturnsTheCountsForAnAnalyst()
        {
            _userRepo.Setup(u => u.GetRoleAsync(It.IsAny<Guid>())).ReturnsAsync("Analyst");
            IReadOnlyList<SlaStateCount> counts = [new SlaStateCount { OverallState = "Breached", RequestCount = 2 }];
            _repo.Setup(r => r.GetSummaryAsync(It.IsAny<SlaViewQuery>())).ReturnsAsync(counts);

            var result = await _sut.GetSummaryAsync(new SlaViewQuery { ActorUserId = Guid.NewGuid() });

            Assert.Equal(2, Assert.Single(result).RequestCount);
        }
    }
}
