namespace Humaid.RiskGovernance.AdminUI.UnitTests.Ai
{
    using Humaid.RiskGovernance.AdminUI.AI;
    using Microsoft.Extensions.Configuration;
    using Microsoft.Extensions.Logging.Abstractions;
    using Moq;
    using Xunit;

    /// <summary>
    /// Flagged in PR #53 review: no coverage for the auth-header branching that decides whether AI
    /// calls authenticate at all. See ClaudeApiClient's own comment for why sk-ant-oat... tokens
    /// (Claude Code/Agent SDK OAuth, from `claude setup-token`) need Authorization: Bearer instead
    /// of the x-api-key header standard sk-ant-api03... keys use - confirmed against the real
    /// Anthropic endpoint (x-api-key returns 401 for an oat01 token even though it's valid).
    /// </summary>
    public class ClaudeApiClientTests
    {
        private static IConfiguration ConfigurationWith(params (string Key, string Value)[] values) =>
            new ConfigurationBuilder()
                .AddInMemoryCollection(Array.ConvertAll(values, v => new KeyValuePair<string, string?>(v.Key, v.Value)))
                .Build();

        private static (HttpClient HttpClient, IHttpClientFactory Factory) NewHttpClientFactory()
        {
            var httpClient = new HttpClient { BaseAddress = new Uri("https://api.anthropic.com") };
            var factory = new Mock<IHttpClientFactory>();
            factory.Setup(f => f.CreateClient("AnthropicApi")).Returns(httpClient);
            return (httpClient, factory.Object);
        }

        [Fact]
        public void Constructor_UsesBearerAuth_ForOAuthToken()
        {
            var (httpClient, factory) = NewHttpClientFactory();
            var configuration = ConfigurationWith(("ANTHROPIC_API_KEY", "sk-ant-oat01-abc123"), ("ANTHROPIC_MODEL", "claude-sonnet-5"));

            _ = new ClaudeApiClient(factory, configuration, NullLogger<ClaudeApiClient>.Instance);

            Assert.Equal("Bearer", httpClient.DefaultRequestHeaders.Authorization?.Scheme);
            Assert.Equal("sk-ant-oat01-abc123", httpClient.DefaultRequestHeaders.Authorization?.Parameter);
            Assert.False(httpClient.DefaultRequestHeaders.Contains("x-api-key"));
        }

        [Fact]
        public void Constructor_UsesXApiKeyHeader_ForStandardApiKey()
        {
            var (httpClient, factory) = NewHttpClientFactory();
            var configuration = ConfigurationWith(("ANTHROPIC_API_KEY", "sk-ant-api03-abc123"), ("ANTHROPIC_MODEL", "claude-sonnet-5"));

            _ = new ClaudeApiClient(factory, configuration, NullLogger<ClaudeApiClient>.Instance);

            Assert.Null(httpClient.DefaultRequestHeaders.Authorization);
            Assert.True(httpClient.DefaultRequestHeaders.Contains("x-api-key"));
            Assert.Equal("sk-ant-api03-abc123", httpClient.DefaultRequestHeaders.GetValues("x-api-key").Single());
        }

        [Fact]
        public async Task CompleteAsync_ThrowsWhenApiKeyIsMissing()
        {
            var (_, factory) = NewHttpClientFactory();
            var configuration = ConfigurationWith(("ANTHROPIC_MODEL", "claude-sonnet-5"));
            var sut = new ClaudeApiClient(factory, configuration, NullLogger<ClaudeApiClient>.Instance);

            await Assert.ThrowsAsync<InvalidOperationException>(() => sut.CompleteAsync("system", "user"));
        }

        [Fact]
        public async Task CompleteAsync_ThrowsWhenModelIsMissing()
        {
            var (_, factory) = NewHttpClientFactory();
            var configuration = ConfigurationWith(("ANTHROPIC_API_KEY", "sk-ant-api03-abc123"));
            var sut = new ClaudeApiClient(factory, configuration, NullLogger<ClaudeApiClient>.Instance);

            await Assert.ThrowsAsync<InvalidOperationException>(() => sut.CompleteAsync("system", "user"));
        }
    }
}
