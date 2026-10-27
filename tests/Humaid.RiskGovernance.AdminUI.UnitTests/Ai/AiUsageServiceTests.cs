namespace Humaid.RiskGovernance.AdminUI.UnitTests.Ai
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.AiUsage;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.AiUsage;
    using Humaid.RiskGovernance.AdminUI.Services.AiUsage;
    using Moq;
    using Xunit;

    /// <summary>
    /// The per-request token totals are plain arithmetic over what the provider reported. A count the
    /// provider did not report (null) adds nothing, so a total can only under-report, never invent usage.
    /// </summary>
    public class AiUsageServiceTests
    {
        private static AiCall Call(string operation, long? input, long? output, long? cacheRead = null, long? cacheCreation = null) =>
            new()
            {
                Id = Guid.NewGuid(),
                Operation = operation,
                Provider = "anthropic",
                InputTokens = input,
                OutputTokens = output,
                CacheReadTokens = cacheRead,
                CacheCreationTokens = cacheCreation,
            };

        [Fact]
        public async Task GetForRequestAsync_SumsEachTokenTypeAndGroupsByStep()
        {
            var requestId = Guid.NewGuid();
            var repo = new Mock<IAiCallLogRepo>();
            repo.Setup(r => r.GetForRequestAsync(requestId)).ReturnsAsync(new List<AiCall>
            {
                Call("category_mapping", 100, 40),
                Call("category_mapping", 10, 5),
                Call("narrative_drafting", 300, 120, 30, 8),
            });
            var sut = new AiUsageService(repo.Object);

            var usage = await sut.GetForRequestAsync(requestId);

            Assert.Equal(3, usage.CallCount);
            Assert.Equal(410, usage.InputTokens);
            Assert.Equal(165, usage.OutputTokens);
            Assert.Equal(30, usage.CacheReadTokens);
            Assert.Equal(8, usage.CacheCreationTokens);
            Assert.Equal(
                [("category_mapping", 2, 110L, 45L), ("narrative_drafting", 1, 300L, 120L)],
                usage.ByOperation.Select(o => (o.Operation, o.Calls, o.InputTokens, o.OutputTokens)).ToArray());
        }

        [Fact]
        public void Summarize_TreatsAnUnreportedCountAsNothing_NotAsAnError()
        {
            var usage = AiUsageService.Summarize([Call("category_mapping", 50, null), Call("category_mapping", null, 7)]);

            Assert.Equal(2, usage.CallCount);
            Assert.Equal(50, usage.InputTokens);
            Assert.Equal(7, usage.OutputTokens);
        }

        [Fact]
        public void Summarize_ReturnsZeroTotalsForARequestWithNoCalls()
        {
            var usage = AiUsageService.Summarize([]);

            Assert.Equal(0, usage.CallCount);
            Assert.Equal(0, usage.InputTokens);
            Assert.Empty(usage.ByOperation);
        }
    }
}
