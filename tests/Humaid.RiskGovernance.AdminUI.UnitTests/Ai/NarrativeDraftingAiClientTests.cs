namespace Humaid.RiskGovernance.AdminUI.UnitTests.Ai
{
    using Humaid.RiskGovernance.AdminUI.AI;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Ai;
    using Xunit;

    public class NarrativeDraftingAiClientTests
    {
        private static NarrativeDraftInput Input(string? regenerationFeedback = null) => new()
        {
            ChangeType = "Product",
            ChangeTitle = "Launch wire transfer product",
            ChangeDescription = "d",
            RiskCategoryId = Guid.NewGuid(),
            CategoryName = "Products & Services",
            CategoryCitation = "FFIEC ... Products and Services",
            ReliedUponPolicyExcerpts = ["[citation] excerpt text"],
            ExtractedFieldFacts = ["product_type: WireTransfer"],
            RegenerationFeedback = regenerationFeedback,
        };

        [Fact]
        public async Task DraftAsync_ParsesNarrativeTextAndUnsupportedClaims()
        {
            const string response = """{"narrativeText": "This is the drafted narrative.", "unsupportedClaims": ["an unverifiable claim"]}""";
            var sut = new NarrativeDraftingAiClient(new FakeChatCompletionClient(response));

            var result = await sut.DraftAsync(Input());

            Assert.Equal("This is the drafted narrative.", result.NarrativeText);
            Assert.Equal(["an unverifiable claim"], result.UnsupportedClaims);
        }

        [Fact]
        public async Task DraftAsync_FallsBackToAReviewableResultOnUnparseableResponse()
        {
            var sut = new NarrativeDraftingAiClient(new FakeChatCompletionClient("not json"));

            var result = await sut.DraftAsync(Input());

            // Never silently empty/blank - the analyst must see *something* flagging what happened,
            // not a mysteriously empty narrative with no explanation (US-6.3's own spirit).
            Assert.Equal(string.Empty, result.NarrativeText);
            Assert.NotEmpty(result.UnsupportedClaims);
        }

        [Fact]
        public async Task DraftAsync_IncludesRegenerationFeedbackInThePromptWhenSupplied()
        {
            var fake = new FakeChatCompletionClient("""{"narrativeText": "revised", "unsupportedClaims": []}""");
            var sut = new NarrativeDraftingAiClient(fake);

            await sut.DraftAsync(Input(regenerationFeedback: "Emphasize the correspondent banking risk more strongly."));

            Assert.Contains("correspondent banking risk", fake.LastUserPrompt);
        }
    }
}
