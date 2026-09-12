namespace Humaid.RiskGovernance.AdminUI.UnitTests.Assessment
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Assessment;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.CategoryMapping;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Narrative;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.PolicyResearch;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Narrative;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.PolicyResearch;
    using Humaid.RiskGovernance.AdminUI.Services.Assessment;
    using Moq;
    using Xunit;
    using CategoryMappingRecord = Humaid.RiskGovernance.AdminUI.Infrastructure.Models.CategoryMapping.CategoryMapping;

    /// <summary>
    /// US-6.3 - the finalization gate. This is the single chokepoint enforcing CLAUDE.md's
    /// "don't let an AI output reach the committee stage without a corresponding review gate in
    /// code": until <see cref="AssessmentService.FinalizeAsync"/> passes, nothing can be routed to
    /// committee (CommitteeService.CastVoteAsync refuses a vote on anything not already in
    /// PendingCommittee). So every assertion here about what BLOCKS finalization is really an
    /// assertion that an unreviewed AI draft cannot reach a human decision-maker.
    /// <para>
    /// Two acceptance criteria are load-bearing and tested explicitly rather than implied:
    /// US-6.3 AC1 ("blocks finalization and LISTS what is outstanding" - the message must name the
    /// categories, not merely refuse) and US-3.2 AC2 (a mapped category with no policy-reliance
    /// decision blocks finalization).
    /// </para>
    /// </summary>
    public class AssessmentServiceTests
    {
        private static readonly Guid AssessmentId = Guid.NewGuid();
        private static readonly Guid AnalystId = Guid.NewGuid();
        private static readonly Guid ProductsCategoryId = Guid.NewGuid();
        private static readonly Guid GeographyCategoryId = Guid.NewGuid();

        private const string ProductsCategoryName = "Products & Services";
        private const string GeographyCategoryName = "Geographic Locations";

        private readonly Mock<IAssessmentRepo> _assessmentRepo = new();
        private readonly Mock<ICategoryMappingRepo> _categoryMappingRepo = new();
        private readonly Mock<INarrativeSectionRepo> _narrativeSectionRepo = new();
        private readonly Mock<IPolicyResearchRepo> _policyResearchRepo = new();
        private readonly AssessmentService _sut;

        public AssessmentServiceTests()
        {
            _sut = new AssessmentService(
                _assessmentRepo.Object,
                _categoryMappingRepo.Object,
                _narrativeSectionRepo.Object,
                _policyResearchRepo.Object);
        }

        [Fact]
        public async Task FinalizeAsync_BlocksAndNamesTheCategoryWhenItsNarrativeIsStillAiDrafted()
        {
            // The core US-5.1 AC2 guarantee: a section still labelled "AI-drafted - pending
            // analyst review" cannot be routed to committee in that state.
            Given(
                categories: [Category(ProductsCategoryId, ProductsCategoryName)],
                sections: [Section(ProductsCategoryId, "AiDrafted")],
                reliance: [Reliance(ProductsCategoryId)]);

            var ex = await Assert.ThrowsAsync<InvalidOperationException>(
                () => _sut.FinalizeAsync(AssessmentId, AnalystId));

            Assert.Contains("Narrative not yet reviewed", ex.Message);
            Assert.Contains(ProductsCategoryName, ex.Message);
        }

        [Fact]
        public async Task FinalizeAsync_BlocksWhenAMappedCategoryHasNoNarrativeSectionAtAll()
        {
            // A category mapped but never drafted is just as unreviewed as one still AiDrafted -
            // the absence of a section must not read as "nothing outstanding".
            Given(
                categories: [Category(ProductsCategoryId, ProductsCategoryName)],
                sections: [],
                reliance: [Reliance(ProductsCategoryId)]);

            var ex = await Assert.ThrowsAsync<InvalidOperationException>(
                () => _sut.FinalizeAsync(AssessmentId, AnalystId));

            Assert.Contains(ProductsCategoryName, ex.Message);
        }

        [Fact]
        public async Task FinalizeAsync_BlocksWhenAMappedCategoryHasNoPolicyRelianceDecision()
        {
            // US-3.2 AC2 - the analyst must have reviewed at least one surfaced policy per mapped
            // category before the assessment can be finalized.
            Given(
                categories: [Category(ProductsCategoryId, ProductsCategoryName)],
                sections: [Section(ProductsCategoryId, "AnalystReviewed")],
                reliance: []);

            var ex = await Assert.ThrowsAsync<InvalidOperationException>(
                () => _sut.FinalizeAsync(AssessmentId, AnalystId));

            Assert.Contains("No policy reviewed", ex.Message);
            Assert.Contains(ProductsCategoryName, ex.Message);
        }

        [Fact]
        public async Task FinalizeAsync_NeverFinalizesTheAssessmentWhenBlocked()
        {
            // The assertion that actually matters for governance: a blocked finalize must not
            // reach the repo at all. Throwing AFTER persisting would still let an unreviewed
            // assessment into PendingCommittee.
            Given(
                categories: [Category(ProductsCategoryId, ProductsCategoryName)],
                sections: [Section(ProductsCategoryId, "AiDrafted")],
                reliance: []);

            await Assert.ThrowsAsync<InvalidOperationException>(
                () => _sut.FinalizeAsync(AssessmentId, AnalystId));

            _assessmentRepo.Verify(r => r.FinalizeAsync(It.IsAny<Guid>(), It.IsAny<Guid>()), Times.Never);
        }

        [Fact]
        public async Task FinalizeAsync_ListsEveryOutstandingReasonNotJustTheFirst()
        {
            // US-6.3 AC1 - "lists what is outstanding". An analyst who fixes only the first
            // complaint and resubmits should not then discover a second one; both categories and
            // both KINDS of gap are reported in a single message.
            Given(
                categories:
                [
                    Category(ProductsCategoryId, ProductsCategoryName),
                    Category(GeographyCategoryId, GeographyCategoryName),
                ],
                sections: [Section(ProductsCategoryId, "AnalystReviewed")],
                reliance: [Reliance(ProductsCategoryId)]);

            var ex = await Assert.ThrowsAsync<InvalidOperationException>(
                () => _sut.FinalizeAsync(AssessmentId, AnalystId));

            Assert.Contains("Narrative not yet reviewed", ex.Message);
            Assert.Contains("No policy reviewed", ex.Message);
            Assert.Contains(GeographyCategoryName, ex.Message);
        }

        [Fact]
        public async Task FinalizeAsync_RecordsTheFinalizingAnalystWhenEveryGateIsSatisfied()
        {
            // US-6.3 AC3 - the finalizing identity is recorded and is a real analyst; this
            // "cannot be anonymous or attributed to 'system'".
            Given(
                categories: [Category(ProductsCategoryId, ProductsCategoryName)],
                sections: [Section(ProductsCategoryId, "AnalystReviewed")],
                reliance: [Reliance(ProductsCategoryId)]);

            await _sut.FinalizeAsync(AssessmentId, AnalystId);

            _assessmentRepo.Verify(r => r.FinalizeAsync(AssessmentId, AnalystId), Times.Once);
        }

        [Theory]
        [InlineData("AnalystReviewed")] // accepted as-is
        [InlineData("AnalystEdited")]   // edited, then accepted
        public async Task CheckReadinessAsync_TreatsAReviewedOrEditedSectionAsSatisfied(string status)
        {
            // US-6.3 AC2 - "all sections are reviewed (accepted as-is or edited)". Both terminal
            // statuses clear the gate; only AiDrafted blocks.
            Given(
                categories: [Category(ProductsCategoryId, ProductsCategoryName)],
                sections: [Section(ProductsCategoryId, status)],
                reliance: [Reliance(ProductsCategoryId)]);

            var readiness = await _sut.CheckReadinessAsync(AssessmentId);

            Assert.True(readiness.IsReady);
            Assert.Empty(readiness.OutstandingNarrativeSections);
        }

        [Fact]
        public async Task CheckReadinessAsync_IgnoresACategoryTheAnalystDeactivated()
        {
            // Epic 2 override - a category the analyst removed (IsActive false) is no longer part
            // of the assessment, so it must not hold finalization hostage for a narrative and a
            // policy decision it will never have.
            Given(
                categories:
                [
                    Category(ProductsCategoryId, ProductsCategoryName),
                    Category(GeographyCategoryId, GeographyCategoryName, isActive: false),
                ],
                sections: [Section(ProductsCategoryId, "AnalystReviewed")],
                reliance: [Reliance(ProductsCategoryId)]);

            var readiness = await _sut.CheckReadinessAsync(AssessmentId);

            Assert.True(readiness.IsReady);
            Assert.DoesNotContain(GeographyCategoryName, readiness.OutstandingNarrativeSections);
            Assert.DoesNotContain(GeographyCategoryName, readiness.CategoriesMissingPolicyReliance);
        }

        [Fact]
        public async Task CheckReadinessAsync_AcceptsAnAssessmentWideRelianceForEveryMappedCategory()
        {
            // A reliance row with a null RiskCategoryId is recorded against the assessment as a
            // whole rather than against one category, and satisfies all of them - see
            // AssessmentService's `r.RiskCategoryId == null ||` branch.
            Given(
                categories:
                [
                    Category(ProductsCategoryId, ProductsCategoryName),
                    Category(GeographyCategoryId, GeographyCategoryName),
                ],
                sections:
                [
                    Section(ProductsCategoryId, "AnalystReviewed"),
                    Section(GeographyCategoryId, "AnalystEdited"),
                ],
                reliance: [Reliance(riskCategoryId: null)]);

            var readiness = await _sut.CheckReadinessAsync(AssessmentId);

            Assert.True(readiness.IsReady);
            Assert.Empty(readiness.CategoriesMissingPolicyReliance);
        }

        [Fact]
        public async Task CheckReadinessAsync_ReportsReadyWhenNoCategoriesAreMappedAtAll()
        {
            // CHARACTERIZATION TEST - documents current behaviour, which is arguably a gap rather
            // than a guarantee. With zero active categories both readiness loops are no-ops, so
            // IsReady is vacuously true and FinalizeAsync will route an assessment to committee
            // with no narrative and no policy review whatsoever.
            //
            // Reachable when the AI proposes nothing (US-2.1 AC3's "no framework mapping
            // configured" path, which correctly returns an empty list rather than guessing) or
            // when an analyst deactivates every proposed category. Raised with the team as a
            // defect candidate; pinned here so that any future change to the behaviour is a
            // deliberate, visible decision rather than an accident.
            Given(categories: [], sections: [], reliance: []);

            var readiness = await _sut.CheckReadinessAsync(AssessmentId);

            Assert.True(readiness.IsReady);
        }

        [Fact]
        public async Task OpenWorkspaceAsync_DelegatesToTheRepo()
        {
            var changeRequestId = Guid.NewGuid();
            _assessmentRepo.Setup(r => r.GetOrCreateAsync(changeRequestId)).ReturnsAsync(AssessmentId);

            var result = await _sut.OpenWorkspaceAsync(changeRequestId);

            Assert.Equal(AssessmentId, result);
            _assessmentRepo.Verify(r => r.GetOrCreateAsync(changeRequestId), Times.Once);
        }

        private void Given(
            IReadOnlyList<CategoryMappingRecord> categories,
            IReadOnlyList<NarrativeSection> sections,
            IReadOnlyList<PolicyReliance> reliance)
        {
            _categoryMappingRepo.Setup(r => r.GetMappingAsync(AssessmentId)).ReturnsAsync(categories);
            _narrativeSectionRepo.Setup(r => r.GetSectionsAsync(AssessmentId)).ReturnsAsync(sections);
            _policyResearchRepo.Setup(r => r.GetRelianceAsync(AssessmentId)).ReturnsAsync(reliance);
        }

        private static CategoryMappingRecord Category(Guid riskCategoryId, string categoryName, bool isActive = true) =>
            new()
            {
                Id = Guid.NewGuid(),
                RiskCategoryId = riskCategoryId,
                CategoryName = categoryName,
                CategoryCode = categoryName.ToUpperInvariant(),
                CitationSection = "FFIEC BSA/AML Manual",
                Source = "AiProposed",
                IsActive = isActive,
            };

        private static NarrativeSection Section(Guid riskCategoryId, string status) =>
            new()
            {
                Id = Guid.NewGuid(),
                RiskCategoryId = riskCategoryId,
                NarrativeText = "Draft narrative text.",
                Status = status,
            };

        private static PolicyReliance Reliance(Guid? riskCategoryId) =>
            new()
            {
                Id = Guid.NewGuid(),
                RiskCategoryId = riskCategoryId,
                PolicyChunkId = Guid.NewGuid(),
                Decision = "ReliedUpon",
            };
    }
}
