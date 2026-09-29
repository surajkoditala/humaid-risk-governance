namespace Humaid.RiskGovernance.AdminUI.UnitTests.Assessment
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Assessment;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.CategoryMapping;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Narrative;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.PolicyResearch;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Scoring;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Users;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.CategoryMapping;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Narrative;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.PolicyResearch;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Scoring;
    using Humaid.RiskGovernance.AdminUI.Services.Assessment;
    using Moq;
    using Xunit;

    /// <summary>US-6.3's readiness gate (DEF-001's zero-category/zero-score backstops) and
    /// DEF-002's actor-role guard on finalization.</summary>
    public class AssessmentServiceTests
    {
        private readonly Mock<IAssessmentRepo> _assessmentRepo = new();
        private readonly Mock<ICategoryMappingRepo> _categoryMappingRepo = new();
        private readonly Mock<INarrativeSectionRepo> _narrativeSectionRepo = new();
        private readonly Mock<IPolicyResearchRepo> _policyResearchRepo = new();
        private readonly Mock<IRiskScoreRepo> _riskScoreRepo = new();
        private readonly Mock<IUserRepo> _userRepo = new();
        private readonly AssessmentService _sut;
        private readonly Guid _riskCategoryId = Guid.NewGuid();

        public AssessmentServiceTests()
        {
            _userRepo.Setup(u => u.GetRoleAsync(It.IsAny<Guid>())).ReturnsAsync("Analyst");
            _sut = new AssessmentService(
                _assessmentRepo.Object, _categoryMappingRepo.Object, _narrativeSectionRepo.Object,
                _policyResearchRepo.Object, _riskScoreRepo.Object, _userRepo.Object);
        }

        private void SetUpFullyReadyAssessment()
        {
            _categoryMappingRepo.Setup(r => r.GetMappingAsync(It.IsAny<Guid>()))
                .ReturnsAsync([new CategoryMapping { RiskCategoryId = _riskCategoryId, CategoryName = "Products & Services", IsActive = true }]);
            _narrativeSectionRepo.Setup(r => r.GetSectionsAsync(It.IsAny<Guid>()))
                .ReturnsAsync([new NarrativeSection { RiskCategoryId = _riskCategoryId, Status = "AnalystReviewed" }]);
            _policyResearchRepo.Setup(r => r.GetRelianceAsync(It.IsAny<Guid>()))
                .ReturnsAsync([new PolicyReliance { RiskCategoryId = _riskCategoryId, Decision = "ReliedUpon" }]);
            _riskScoreRepo.Setup(r => r.GetScoresAsync(It.IsAny<Guid>()))
                .ReturnsAsync([new RiskScore { RiskCategoryId = _riskCategoryId }]);
        }

        [Fact]
        public async Task FinalizeAsync_RejectsNonAnalystActor()
        {
            _userRepo.Setup(u => u.GetRoleAsync(It.IsAny<Guid>())).ReturnsAsync("ProductOwner");
            SetUpFullyReadyAssessment();

            await Assert.ThrowsAsync<ValidationException>(() => _sut.FinalizeAsync(Guid.NewGuid(), Guid.NewGuid()));
            _assessmentRepo.Verify(r => r.FinalizeAsync(It.IsAny<Guid>(), It.IsAny<Guid>()), Times.Never);
        }

        [Fact]
        public async Task FinalizeAsync_AllowsAdminActor()
        {
            _userRepo.Setup(u => u.GetRoleAsync(It.IsAny<Guid>())).ReturnsAsync("Admin");
            SetUpFullyReadyAssessment();

            await _sut.FinalizeAsync(Guid.NewGuid(), Guid.NewGuid());

            _assessmentRepo.Verify(r => r.FinalizeAsync(It.IsAny<Guid>(), It.IsAny<Guid>()), Times.Once);
        }

        [Fact]
        public async Task FinalizeAsync_RejectsWhenNoCategoriesAreMapped()
        {
            // DEF-001: zero mapped categories must never read as "ready" - there is nothing here
            // for a human to have reviewed.
            _categoryMappingRepo.Setup(r => r.GetMappingAsync(It.IsAny<Guid>())).ReturnsAsync([]);

            var ex = await Assert.ThrowsAsync<ValidationException>(() => _sut.FinalizeAsync(Guid.NewGuid(), Guid.NewGuid()));
            Assert.Contains("No risk categories are mapped", ex.Message);
            _assessmentRepo.Verify(r => r.FinalizeAsync(It.IsAny<Guid>(), It.IsAny<Guid>()), Times.Never);
        }

        [Fact]
        public async Task FinalizeAsync_RejectsWhenACategoryHasNoScoreYet()
        {
            // DEF-001's own suggested fix: a fully-mapped, fully-reviewed assessment with nothing
            // calculated in Epic 7 must still be blocked.
            _categoryMappingRepo.Setup(r => r.GetMappingAsync(It.IsAny<Guid>()))
                .ReturnsAsync([new CategoryMapping { RiskCategoryId = _riskCategoryId, CategoryName = "Products & Services", IsActive = true }]);
            _narrativeSectionRepo.Setup(r => r.GetSectionsAsync(It.IsAny<Guid>()))
                .ReturnsAsync([new NarrativeSection { RiskCategoryId = _riskCategoryId, Status = "AnalystReviewed" }]);
            _policyResearchRepo.Setup(r => r.GetRelianceAsync(It.IsAny<Guid>()))
                .ReturnsAsync([new PolicyReliance { RiskCategoryId = _riskCategoryId, Decision = "ReliedUpon" }]);
            _riskScoreRepo.Setup(r => r.GetScoresAsync(It.IsAny<Guid>())).ReturnsAsync([]);

            var ex = await Assert.ThrowsAsync<ValidationException>(() => _sut.FinalizeAsync(Guid.NewGuid(), Guid.NewGuid()));
            Assert.Contains("No score calculated for", ex.Message);
        }

        [Fact]
        public async Task FinalizeAsync_RejectsWhenNarrativeIsStillOnlyAiDrafted()
        {
            _categoryMappingRepo.Setup(r => r.GetMappingAsync(It.IsAny<Guid>()))
                .ReturnsAsync([new CategoryMapping { RiskCategoryId = _riskCategoryId, CategoryName = "Products & Services", IsActive = true }]);
            _narrativeSectionRepo.Setup(r => r.GetSectionsAsync(It.IsAny<Guid>()))
                .ReturnsAsync([new NarrativeSection { RiskCategoryId = _riskCategoryId, Status = "AiDrafted" }]);
            _policyResearchRepo.Setup(r => r.GetRelianceAsync(It.IsAny<Guid>()))
                .ReturnsAsync([new PolicyReliance { RiskCategoryId = _riskCategoryId, Decision = "ReliedUpon" }]);
            _riskScoreRepo.Setup(r => r.GetScoresAsync(It.IsAny<Guid>()))
                .ReturnsAsync([new RiskScore { RiskCategoryId = _riskCategoryId }]);

            var ex = await Assert.ThrowsAsync<ValidationException>(() => _sut.FinalizeAsync(Guid.NewGuid(), Guid.NewGuid()));
            Assert.Contains("Narrative not yet reviewed", ex.Message);
        }
    }
}
