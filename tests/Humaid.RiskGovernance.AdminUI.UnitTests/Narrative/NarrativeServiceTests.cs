namespace Humaid.RiskGovernance.AdminUI.UnitTests.Narrative
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Ai;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Assessment;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.CategoryMapping;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.ChangeRequests;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.DocumentExtraction;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Narrative;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.PolicyResearch;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Narrative;
    using Humaid.RiskGovernance.AdminUI.Services.Narrative;
    using Moq;
    using Xunit;

    /// <summary>DEF-007: a Finalized assessment's narrative must lock from further edits - draft,
    /// review, and edit all check this the same way.</summary>
    public class NarrativeServiceTests
    {
        private readonly Mock<INarrativeSectionRepo> _narrativeSectionRepo = new();
        private readonly Mock<IAssessmentRepo> _assessmentRepo = new();
        private readonly Mock<IChangeRequestRepo> _changeRequestRepo = new();
        private readonly Mock<ICategoryMappingRepo> _categoryMappingRepo = new();
        private readonly Mock<IPolicyResearchRepo> _policyResearchRepo = new();
        private readonly Mock<IExtractedFieldRepo> _extractedFieldRepo = new();
        private readonly Mock<INarrativeDraftingAiClient> _aiClient = new();
        private readonly NarrativeService _sut;

        public NarrativeServiceTests()
        {
            _sut = new NarrativeService(
                _narrativeSectionRepo.Object, _assessmentRepo.Object, _changeRequestRepo.Object,
                _categoryMappingRepo.Object, _policyResearchRepo.Object, _extractedFieldRepo.Object, _aiClient.Object);
        }

        [Fact]
        public async Task ReviewAsync_RejectsWhenAssessmentIsFinalized()
        {
            var assessmentId = Guid.NewGuid();
            _assessmentRepo.Setup(r => r.GetByIdAsync(assessmentId))
                .ReturnsAsync(new Infrastructure.Models.Assessment.Assessment { Status = "Finalized" });

            await Assert.ThrowsAsync<ValidationException>(() => _sut.ReviewAsync(assessmentId, Guid.NewGuid(), Guid.NewGuid()));
            _narrativeSectionRepo.Verify(r => r.ReviewAsync(It.IsAny<Guid>(), It.IsAny<Guid>(), It.IsAny<Guid>()), Times.Never);
        }

        [Fact]
        public async Task EditAsync_RejectsWhenAssessmentIsFinalized()
        {
            var assessmentId = Guid.NewGuid();
            _assessmentRepo.Setup(r => r.GetByIdAsync(assessmentId))
                .ReturnsAsync(new Infrastructure.Models.Assessment.Assessment { Status = "Finalized" });
            var input = new EditNarrativeSectionInput { AssessmentId = assessmentId, RiskCategoryId = Guid.NewGuid(), NewText = "edited", Reason = "correction", ActorUserId = Guid.NewGuid() };

            await Assert.ThrowsAsync<ValidationException>(() => _sut.EditAsync(input));
            _narrativeSectionRepo.Verify(r => r.EditAsync(It.IsAny<EditNarrativeSectionInput>()), Times.Never);
        }

        [Fact]
        public async Task DraftAsync_RejectsWhenAssessmentIsFinalized()
        {
            var assessmentId = Guid.NewGuid();
            _assessmentRepo.Setup(r => r.GetByIdAsync(assessmentId))
                .ReturnsAsync(new Infrastructure.Models.Assessment.Assessment { Status = "Finalized" });

            await Assert.ThrowsAsync<ValidationException>(() => _sut.DraftAsync(assessmentId, Guid.NewGuid()));
            _aiClient.Verify(c => c.DraftAsync(It.IsAny<Infrastructure.Models.Ai.NarrativeDraftInput>()), Times.Never);
        }

        [Fact]
        public async Task DraftAsync_RejectsCategoryNotActivelyMappedToThisAssessment()
        {
            // The citation-fabrication guard's Narrative-side counterpart: never draft against a
            // category the assessment doesn't actually have mapped (or that's been un-mapped).
            var assessmentId = Guid.NewGuid();
            var changeRequestId = Guid.NewGuid();
            _assessmentRepo.Setup(r => r.GetByIdAsync(assessmentId))
                .ReturnsAsync(new Infrastructure.Models.Assessment.Assessment { Status = "Draft", ChangeRequestId = changeRequestId });
            _changeRequestRepo.Setup(r => r.GetByIdAsync(changeRequestId))
                .ReturnsAsync(new Infrastructure.Models.ChangeRequests.ChangeRequest { Id = changeRequestId, ChangeType = "Product", Title = "t", Description = "d" });
            _categoryMappingRepo.Setup(r => r.GetMappingAsync(assessmentId)).ReturnsAsync([]);

            await Assert.ThrowsAsync<ValidationException>(() => _sut.DraftAsync(assessmentId, Guid.NewGuid()));
            _aiClient.Verify(c => c.DraftAsync(It.IsAny<Infrastructure.Models.Ai.NarrativeDraftInput>()), Times.Never);
        }
    }
}
