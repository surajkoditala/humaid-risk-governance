namespace Humaid.RiskGovernance.AdminUI.UnitTests.Ai
{
    using Humaid.RiskGovernance.AdminUI.AI;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Ai;
    using Microsoft.Extensions.Logging.Abstractions;
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
            var sut = new NarrativeDraftingAiClient(new FakeChatCompletionClient(response), NullLogger<NarrativeDraftingAiClient>.Instance);

            var result = await sut.DraftAsync(Input());

            Assert.Equal("This is the drafted narrative.", result.NarrativeText);
            Assert.Equal(["an unverifiable claim"], result.UnsupportedClaims);
        }

        [Fact]
        public async Task DraftAsync_ParsesParagraphsSentAsRawLineBreaksInsideTheJsonString()
        {
            // CR-2026-00109 in dev: the model put literal newlines between paragraphs instead of \n.
            const string response = "{\"narrativeText\": \"First paragraph.\n\nSecond \\\"quoted\\\" paragraph.\r\n\tThird.\",\n  \"unsupportedClaims\": [\"a claim\nover two lines\"]\n}";
            var sut = new NarrativeDraftingAiClient(new FakeChatCompletionClient(response), NullLogger<NarrativeDraftingAiClient>.Instance);

            var result = await sut.DraftAsync(Input());

            Assert.Equal("First paragraph.\n\nSecond \"quoted\" paragraph.\r\n\tThird.", result.NarrativeText);
            Assert.Equal(["a claim\nover two lines"], result.UnsupportedClaims);
        }

        [Fact]
        public async Task DraftAsync_FallsBackToAReviewableResultOnUnparseableResponse()
        {
            var sut = new NarrativeDraftingAiClient(new FakeChatCompletionClient("not json"), NullLogger<NarrativeDraftingAiClient>.Instance);

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
            var sut = new NarrativeDraftingAiClient(fake, NullLogger<NarrativeDraftingAiClient>.Instance);

            await sut.DraftAsync(Input(regenerationFeedback: "Emphasize the correspondent banking risk more strongly."));

            Assert.Contains("correspondent banking risk", fake.LastUserPrompt);
        }
    }
}
