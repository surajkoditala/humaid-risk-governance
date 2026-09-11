namespace Humaid.RiskGovernance.AdminUI.UnitTests.Ai
{
    using Humaid.RiskGovernance.AdminUI.AI;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.RiskFramework;
    using Xunit;

    /// <summary>US-2.1's core grounding requirement: never propose or pass through a category the
    /// caller didn't explicitly allow, no matter what the model returns.</summary>
    public class CategoryMappingAiClientTests
    {
        private static readonly Guid AllowedCategoryId = Guid.NewGuid();
        private static readonly List<ChangeTypeCategoryDefault> Defaults =
        [
            new() { RiskCategoryId = AllowedCategoryId, Code = "PRODUCTS_SERVICES", CitationSection = "FFIEC ... Products and Services", Weight = "Primary" },
        ];

        [Fact]
        public async Task ProposeAsync_NeverCallsTheModelWhenNoCategoriesAreAllowed()
        {
            var fake = new FakeChatCompletionClient("[]");
            var sut = new CategoryMappingAiClient(fake);

            var result = await sut.ProposeAsync("Process", "t", "d", []);

            Assert.Empty(result);
            Assert.Equal(0, fake.CallCount); // US-2.1 AC3: flag explicitly, don't even ask when nothing's configured
        }

        [Fact]
        public async Task ProposeAsync_DropsAProposalForACategoryOutsideTheAllowedList()
        {
            var fabricatedId = Guid.NewGuid(); // not in Defaults
            var response = $$"""[{"riskCategoryId": "{{AllowedCategoryId}}", "rationale": "legit"}, {"riskCategoryId": "{{fabricatedId}}", "rationale": "fabricated"}]""";
            var sut = new CategoryMappingAiClient(new FakeChatCompletionClient(response));

            var result = await sut.ProposeAsync("Product", "t", "d", Defaults);

            var proposal = Assert.Single(result);
            Assert.Equal(AllowedCategoryId, proposal.RiskCategoryId);
        }

        [Fact]
        public async Task ProposeAsync_ParsesAMarkdownFencedResponse()
        {
            var response = $$"""
                ```json
                [{"riskCategoryId": "{{AllowedCategoryId}}", "rationale": "wrapped in a fence anyway"}]
                ```
                """;
            var sut = new CategoryMappingAiClient(new FakeChatCompletionClient(response));

            var result = await sut.ProposeAsync("Product", "t", "d", Defaults);

            var proposal = Assert.Single(result);
            Assert.Equal("PRODUCTS_SERVICES", proposal.CategoryCode);
        }

        [Fact]
        public async Task ProposeAsync_DegradesToEmptyOnMalformedJson()
        {
            var sut = new CategoryMappingAiClient(new FakeChatCompletionClient("not json at all"));

            var result = await sut.ProposeAsync("Product", "t", "d", Defaults);

            Assert.Empty(result);
        }

        [Fact]
        public async Task ProposeAsync_IncludesExternalContextInThePromptWhenSupplied()
        {
            var fake = new FakeChatCompletionClient($$"""[{"riskCategoryId": "{{AllowedCategoryId}}", "rationale": "r"}]""");
            var sut = new CategoryMappingAiClient(fake);

            await sut.ProposeAsync("CustomerSegment", "t", "d", Defaults, externalContextSummary: "Customer risk context: {\"CustomerType\": \"Corporate\"}");

            Assert.Contains("Corporate", fake.LastUserPrompt);
        }
    }
}
