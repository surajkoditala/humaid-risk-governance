namespace Humaid.RiskGovernance.AdminUI.UnitTests.Scoring
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Scoring;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Scoring;
    using Humaid.RiskGovernance.AdminUI.Services.Scoring;
    using Moq;
    using Xunit;

    /// <summary>
    /// The residual-risk-never-zero rule, in every place ScoringService enforces it in C# -
    /// defense in depth on top of the DB's own CHECK constraints (schema/010_scoring.sql).
    /// </summary>
    public class ScoringServiceTests
    {
        private readonly Mock<IRiskScoreRepo> _repo = new();
        private readonly ScoringService _sut;

        public ScoringServiceTests()
        {
            _sut = new ScoringService(_repo.Object);
        }

        [Theory]
        [InlineData(1.0)]   // exactly 1.0 would let residual reach zero - must be rejected
        [InlineData(1.5)]
        [InlineData(-0.1)]  // negative is nonsensical too
        public async Task UpsertConfigAsync_RejectsOutOfRangeMitigationFactor(decimal factor)
        {
            var input = new UpsertScoringConfigInput { RiskCategoryId = Guid.NewGuid(), MaxMitigationFactor = factor, Reason = "test", ActorUserId = Guid.NewGuid() };

            await Assert.ThrowsAsync<InvalidOperationException>(() => _sut.UpsertConfigAsync(input));
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

            await Assert.ThrowsAsync<InvalidOperationException>(() => _sut.CalculateAsync(input));
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

            await Assert.ThrowsAsync<InvalidOperationException>(() => _sut.OverrideAsync(input));
            _repo.Verify(r => r.OverrideAsync(It.IsAny<OverrideRiskScoreInput>()), Times.Never);
        }

        [Fact]
        public async Task OverrideAsync_RejectsBlankReason()
        {
            var input = new OverrideRiskScoreInput { AssessmentId = Guid.NewGuid(), RiskCategoryId = Guid.NewGuid(), NewResidualRating = 2, Reason = "   " };

            await Assert.ThrowsAsync<InvalidOperationException>(() => _sut.OverrideAsync(input));
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
