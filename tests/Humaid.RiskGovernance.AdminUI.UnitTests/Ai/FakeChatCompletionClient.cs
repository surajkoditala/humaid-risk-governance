namespace Humaid.RiskGovernance.AdminUI.UnitTests.Ai
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Ai;

    /// <summary>
    /// A hand-rolled fake rather than a mocked HttpClient - the AI clients depend on
    /// IChatCompletionClient (Phase 3 Step 1's abstraction), not on Anthropic's/Foundry's wire
    /// format directly, so a test double at that level is simpler and doesn't couple these tests
    /// to either provider's actual HTTP contract.
    /// </summary>
    public class FakeChatCompletionClient : IChatCompletionClient
    {
        private readonly string _response;
        public string? LastUserPrompt { get; private set; }
        public int CallCount { get; private set; }

        public FakeChatCompletionClient(string response)
        {
            _response = response;
        }

        public Task<string> CompleteAsync(string systemPrompt, string userPrompt, CancellationToken cancellationToken = default)
        {
            CallCount++;
            LastUserPrompt = userPrompt;
            return Task.FromResult(_response);
        }
    }
}
