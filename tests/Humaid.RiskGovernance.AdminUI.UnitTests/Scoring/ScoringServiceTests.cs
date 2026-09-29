namespace Humaid.RiskGovernance.AdminUI.UnitTests.Scoring
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Assessment;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Scoring;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Users;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Scoring;
    using Humaid.RiskGovernance.AdminUI.Services.Scoring;
    using Moq;
    using Xunit;

    /// <summary>
    /// The residual-risk-never-zero rule, in every place ScoringService enforces it in C# -
    /// defense in depth on top of the DB's own CHECK constraints (schema/010_scoring.sql) - plus
    /// DEF-002's actor-role guard on configuration changes and DEF-007's finalized-assessment lock.
    /// </summary>
    public class ScoringServiceTests
    {
        private readonly Mock<IRiskScoreRepo> _repo = new();
        private readonly Mock<IUserRepo> _userRepo = new();
        private readonly Mock<IAssessmentRepo> _assessmentRepo = new();
        private readonly ScoringService _sut;

        public ScoringServiceTests()
        {
            // Defaults every test to an actor allowed to change configuration and a not-yet-
            // finalized assessment, so only the DEF-002/DEF-007-specific tests need to override this.
            SetUpActorRole("Analyst");
            _assessmentRepo.Setup(r => r.GetByIdAsync(It.IsAny<Guid>()))
                .ReturnsAsync(new Infrastructure.Models.Assessment.Assessment { Status = "Draft" });
            _sut = new ScoringService(_repo.Object, _userRepo.Object, _assessmentRepo.Object);
        }

        /// <summary>A user can hold more than one role (Epic 11 follow-up), so HasRoleAsync is a
        /// membership check, not equality - these mock "the actor's only role is <paramref
        /// name="role"/>" for tests that only care about a single one, for any actor id or one
        /// specific id (overriding the any-id default for just that actor).</summary>
        private void SetUpActorRole(string role) =>
            _userRepo.Setup(u => u.HasRoleAsync(It.IsAny<Guid>(), It.IsAny<string>()))
                .ReturnsAsync((Guid _, string checkedRole) => checkedRole == role);

        private void SetUpActorRole(Guid userId, string role) =>
            _userRepo.Setup(u => u.HasRoleAsync(userId, It.IsAny<string>()))
                .ReturnsAsync((Guid _, string checkedRole) => checkedRole == role);

        [Fact]
        public async Task CalculateAsync_RejectsWhenAssessmentIsFinalized()
        {
            var assessmentId = Guid.NewGuid();
            _assessmentRepo.Setup(r => r.GetByIdAsync(assessmentId))
                .ReturnsAsync(new Infrastructure.Models.Assessment.Assessment { Status = "Finalized" });
            var input = new CalculateRiskScoreInput { AssessmentId = assessmentId, RiskCategoryId = Guid.NewGuid(), InherentRating = 3, ControlEffectiveness = 0.5m };

            await Assert.ThrowsAsync<ValidationException>(() => _sut.CalculateAsync(input));
            _repo.Verify(r => r.CalculateAndSaveAsync(It.IsAny<CalculateRiskScoreInput>()), Times.Never);
        }

        [Fact]
        public async Task OverrideAsync_RejectsWhenAssessmentIsFinalized()
        {
            var assessmentId = Guid.NewGuid();
            _assessmentRepo.Setup(r => r.GetByIdAsync(assessmentId))
                .ReturnsAsync(new Infrastructure.Models.Assessment.Assessment { Status = "Finalized" });
            var input = new OverrideRiskScoreInput { AssessmentId = assessmentId, RiskCategoryId = Guid.NewGuid(), NewResidualRating = 2, Reason = "analyst judgement" };

            await Assert.ThrowsAsync<ValidationException>(() => _sut.OverrideAsync(input));
            _repo.Verify(r => r.OverrideAsync(It.IsAny<OverrideRiskScoreInput>()), Times.Never);
        }

        [Fact]
        public async Task UpsertConfigAsync_RejectsNonAnalystActor()
        {
            var actorId = Guid.NewGuid();
            SetUpActorRole(actorId, "ProductOwner");
            var input = new UpsertScoringConfigInput { RiskCategoryId = Guid.NewGuid(), MaxMitigationFactor = 0.5m, Reason = "test", ActorUserId = actorId };

            await Assert.ThrowsAsync<ValidationException>(() => _sut.UpsertConfigAsync(input));
            _repo.Verify(r => r.UpsertConfigAsync(It.IsAny<UpsertScoringConfigInput>()), Times.Never);
        }

        [Theory]
        [InlineData(1.0)]   // exactly 1.0 would let residual reach zero - must be rejected
        [InlineData(1.5)]
        [InlineData(-0.1)]  // negative is nonsensical too
        public async Task UpsertConfigAsync_RejectsOutOfRangeMitigationFactor(decimal factor)
        {
            var input = new UpsertScoringConfigInput { RiskCategoryId = Guid.NewGuid(), MaxMitigationFactor = factor, Reason = "test", ActorUserId = Guid.NewGuid() };

            await Assert.ThrowsAsync<ValidationException>(() => _sut.UpsertConfigAsync(input));
            _repo.Verify(r => r.UpsertConfigAsync(It.IsAny<UpsertScoringConfigInput>()), Times.Never);
        }

        [Theory]
        [InlineData(0.0)]
        [InlineData(0.5)]
        [InlineData(0.99)]
        public async Task UpsertConfigAsync_AcceptsInRangeMitigationFactor(decimal factor)
        {
            var input = new UpsertScoringConfigInput { RiskCategoryId = Guid.NewGuid(), MaxMitigationFactor = factor, Reason = "test", ActorUserId = Guid.NewGuid() };
            _repo.Setup(r => r.UpsertConfigAsync(input)).ReturnsAsync(Guid.NewGuid());

            await _sut.UpsertConfigAsync(input);

            _repo.Verify(r => r.UpsertConfigAsync(input), Times.Once);
        }

        [Fact]
        public async Task CalculateAsync_ThrowsIfRepoReturnsNonPositiveResidual()
        {
            // Should be mathematically impossible given the DB's own CHECK constraints, but the
            // service re-validates anyway (defense in depth) - this proves that check is real,
            // not dead code.
            var input = new CalculateRiskScoreInput { AssessmentId = Guid.NewGuid(), RiskCategoryId = Guid.NewGuid(), InherentRating = 3, ControlEffectiveness = 1.0m };
            var scoreId = Guid.NewGuid();
            _repo.Setup(r => r.CalculateAndSaveAsync(input)).ReturnsAsync((scoreId, 0m, 0.5m));

            await Assert.ThrowsAsync<ValidationException>(() => _sut.CalculateAsync(input));
        }

        [Fact]
        public async Task CalculateAsync_ReturnsScoreWhenResidualIsPositive()
        {
            var input = new CalculateRiskScoreInput { AssessmentId = Guid.NewGuid(), RiskCategoryId = Guid.NewGuid(), InherentRating = 3, ControlEffectiveness = 0.5m };
            var scoreId = Guid.NewGuid();
            var expected = new RiskScore { Id = scoreId, ResidualRating = 1.5m };
            _repo.Setup(r => r.CalculateAndSaveAsync(input)).ReturnsAsync((scoreId, 1.5m, 0.5m));
            _repo.Setup(r => r.GetScoresAsync(input.AssessmentId)).ReturnsAsync([expected]);

            var result = await _sut.CalculateAsync(input);

            Assert.Equal(scoreId, result.Id);
            Assert.Equal(1.5m, result.ResidualRating);
        }

        [Fact]
        public async Task OverrideAsync_RejectsNonPositiveResidual()
        {
            var input = new OverrideRiskScoreInput { AssessmentId = Guid.NewGuid(), RiskCategoryId = Guid.NewGuid(), NewResidualRating = 0, Reason = "analyst judgement" };

            await Assert.ThrowsAsync<ValidationException>(() => _sut.OverrideAsync(input));
            _repo.Verify(r => r.OverrideAsync(It.IsAny<OverrideRiskScoreInput>()), Times.Never);
        }

        [Fact]
        public async Task OverrideAsync_RejectsBlankReason()
        {
            var input = new OverrideRiskScoreInput { AssessmentId = Guid.NewGuid(), RiskCategoryId = Guid.NewGuid(), NewResidualRating = 2, Reason = "   " };

            await Assert.ThrowsAsync<ValidationException>(() => _sut.OverrideAsync(input));
            _repo.Verify(r => r.OverrideAsync(It.IsAny<OverrideRiskScoreInput>()), Times.Never);
        }

        [Fact]
        public async Task OverrideAsync_AcceptsPositiveResidualWithReason()
        {
            var input = new OverrideRiskScoreInput { AssessmentId = Guid.NewGuid(), RiskCategoryId = Guid.NewGuid(), NewResidualRating = 2, Reason = "analyst judgement" };
            _repo.Setup(r => r.OverrideAsync(input)).ReturnsAsync(Guid.NewGuid());

            await _sut.OverrideAsync(input);

            _repo.Verify(r => r.OverrideAsync(input), Times.Once);
        }
    }
}
