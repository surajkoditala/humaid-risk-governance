namespace Humaid.RiskGovernance.AdminUI.UnitTests.CategoryMapping
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Ai;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Assessment;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.CategoryMapping;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.ChangeRequests;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.DataIngestion;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.CategoryMapping;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core;
    using Humaid.RiskGovernance.AdminUI.Services.CategoryMapping;
    using Moq;
    using Xunit;

    /// <summary>DEF-007: a Finalized assessment's category mapping must lock from further edits.</summary>
    public class CategoryMappingServiceTests
    {
        private readonly Mock<ICategoryMappingRepo> _categoryMappingRepo = new();
        private readonly Mock<IChangeRequestRepo> _changeRequestRepo = new();
        private readonly Mock<ICategoryMappingAiClient> _aiClient = new();
        private readonly Mock<IDataIngestionService> _dataIngestionService = new();
        private readonly Mock<IAssessmentRepo> _assessmentRepo = new();
        private readonly CategoryMappingService _sut;

        public CategoryMappingServiceTests()
        {
            _assessmentRepo.Setup(r => r.GetByIdAsync(It.IsAny<Guid>()))
                .ReturnsAsync(new Infrastructure.Models.Assessment.Assessment { Status = "Draft" });
            _sut = new CategoryMappingService(
                _categoryMappingRepo.Object, _changeRequestRepo.Object, _aiClient.Object,
                _dataIngestionService.Object, _assessmentRepo.Object);
        }

        [Fact]
        public async Task OverrideAsync_RejectsWhenAssessmentIsFinalized()
        {
            var assessmentId = Guid.NewGuid();
            _assessmentRepo.Setup(r => r.GetByIdAsync(assessmentId))
                .ReturnsAsync(new Infrastructure.Models.Assessment.Assessment { Status = "Finalized" });
            var input = new OverrideCategoryMappingInput { AssessmentId = assessmentId, RiskCategoryId = Guid.NewGuid(), IsActive = false, Reason = "not relevant", ActorUserId = Guid.NewGuid() };

            await Assert.ThrowsAsync<ValidationException>(() => _sut.OverrideAsync(input));
            _categoryMappingRepo.Verify(r => r.OverrideAsync(It.IsAny<OverrideCategoryMappingInput>()), Times.Never);
        }

        [Fact]
        public async Task ProposeAsync_RejectsWhenAssessmentIsFinalized()
        {
            var assessmentId = Guid.NewGuid();
            _assessmentRepo.Setup(r => r.GetByIdAsync(assessmentId))
                .ReturnsAsync(new Infrastructure.Models.Assessment.Assessment { Status = "Finalized" });

            await Assert.ThrowsAsync<ValidationException>(() => _sut.ProposeAsync(assessmentId, Guid.NewGuid()));
            _changeRequestRepo.Verify(r => r.GetByIdAsync(It.IsAny<Guid>()), Times.Never);
        }

        [Fact]
        public async Task OverrideAsync_RejectsWhenAssessmentDoesNotExist()
        {
            var assessmentId = Guid.NewGuid();
            _assessmentRepo.Setup(r => r.GetByIdAsync(assessmentId)).ReturnsAsync((Infrastructure.Models.Assessment.Assessment?)null);
            var input = new OverrideCategoryMappingInput { AssessmentId = assessmentId, RiskCategoryId = Guid.NewGuid(), IsActive = false, Reason = "not relevant", ActorUserId = Guid.NewGuid() };

            await Assert.ThrowsAsync<ValidationException>(() => _sut.OverrideAsync(input));
        }
    }
}
