namespace Humaid.RiskGovernance.AdminUI.UnitTests.Ai
{
    using Humaid.RiskGovernance.AdminUI.AI;
    using Xunit;

    public class DocumentExtractionAiClientTests
    {
        [Fact]
        public async Task ExtractAsync_NeverCallsTheModelForEmptyDocumentText()
        {
            var fake = new FakeChatCompletionClient("[]");
            var sut = new DocumentExtractionAiClient(fake);

            var result = await sut.ExtractAsync("Vendor", "   ");

            Assert.Empty(result);
            Assert.Equal(0, fake.CallCount);
        }

        [Fact]
        public async Task ExtractAsync_ParsesFieldsIncludingNeedsReviewFlag()
        {
            const string response = """
                [
                  {"fieldKey": "vendor_name", "fieldValue": "Global KYC Solutions Inc", "confidence": 0.95, "needsReview": false, "sourceExcerpt": "Vendor name is Global KYC Solutions Inc"},
                  {"fieldKey": "vendor_jurisdiction", "fieldValue": null, "confidence": null, "needsReview": true, "sourceExcerpt": null}
                ]
                """;
            var sut = new DocumentExtractionAiClient(new FakeChatCompletionClient(response));

            var result = await sut.ExtractAsync("Vendor", "some document text");

            Assert.Equal(2, result.Count);
            Assert.False(result[0].NeedsReview);
            Assert.True(result[1].NeedsReview);
            Assert.Null(result[1].FieldValue);
        }

        [Fact]
        public async Task ExtractAsync_DegradesToEmptyOnMalformedJson()
        {
            var sut = new DocumentExtractionAiClient(new FakeChatCompletionClient("{not valid"));

            var result = await sut.ExtractAsync("Vendor", "some document text");

            Assert.Empty(result);
        }
    }
}
