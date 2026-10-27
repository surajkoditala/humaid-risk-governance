namespace Humaid.RiskGovernance.AdminUI.UnitTests.Ai
{
    using System.Net;
    using System.Text;
    using Humaid.RiskGovernance.AdminUI.AI;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Ai;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.AiUsage;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.AiUsage;
    using Microsoft.Extensions.Configuration;
    using Microsoft.Extensions.Logging.Abstractions;
    using Moq;
    using Xunit;

    /// <summary>
    /// Measured token use per change request: a successful AI call is appended to ai_call_log with
    /// the request the calling service named (AiCallContext) and the step the touchpoint client
    /// named (AiUsageTelemetry.BeginOperation); recording must never fail the AI call itself.
    /// </summary>
    public class AiCallLogTests
    {
        private static readonly Guid RequestId = Guid.Parse("a0000000-0000-0000-0000-000000000001");
        private static readonly Guid AssessmentId = Guid.Parse("b0000000-0000-0000-0000-000000000001");

        private static IConfiguration ConfigurationWith(params (string Key, string Value)[] values) =>
            new ConfigurationBuilder()
                .AddInMemoryCollection(Array.ConvertAll(values, v => new KeyValuePair<string, string?>(v.Key, v.Value)))
                .Build();

        private static IHttpClientFactory FactoryReturning(string clientName, string baseAddress, Func<HttpResponseMessage> respond)
        {
            var httpClient = new HttpClient(new StubHandler(respond)) { BaseAddress = new Uri(baseAddress) };
            var factory = new Mock<IHttpClientFactory>();
            factory.Setup(f => f.CreateClient(clientName)).Returns(httpClient);
            return factory.Object;
        }

        private static HttpResponseMessage Json(string body) =>
            new(HttpStatusCode.OK) { Content = new StringContent(body, Encoding.UTF8, "application/json") };

        private static ClaudeApiClient Claude(IAiCallLogRepo? repo, Func<HttpResponseMessage> respond) =>
            new(
                FactoryReturning("AnthropicApi", "https://api.anthropic.com", respond),
                ConfigurationWith(("ANTHROPIC_API_KEY", "sk-ant-api03-abc123"), ("ANTHROPIC_MODEL", "claude-sonnet-5")),
                NullLogger<ClaudeApiClient>.Instance,
                repo);

        private const string ClaudeOk =
            """{"model":"claude-sonnet-5","content":[{"type":"text","text":"{}"}],"usage":{"input_tokens":120,"output_tokens":45,"cache_read_input_tokens":30,"cache_creation_input_tokens":8}}""";

        [Fact]
        public async Task ClaudeClient_AppendsTheCallToTheLog_WithTheRequestAndStepFromTheAmbientScopes()
        {
            var repo = new Mock<IAiCallLogRepo>();
            LogAiCallInput? logged = null;
            repo.Setup(r => r.LogAsync(It.IsAny<LogAiCallInput>()))
                .Callback<LogAiCallInput>(i => logged = i)
                .ReturnsAsync(Guid.NewGuid());
            var sut = Claude(repo.Object, () => Json(ClaudeOk));

            using (AiCallContext.Begin(RequestId, AssessmentId))
            using (AiUsageTelemetry.BeginOperation("category_mapping"))
            {
                await sut.CompleteAsync("system", "user");
            }

            repo.Verify(r => r.LogAsync(It.IsAny<LogAiCallInput>()), Times.Once);
            Assert.NotNull(logged);
            Assert.Equal(RequestId, logged!.ChangeRequestId);
            Assert.Equal(AssessmentId, logged.AssessmentId);
            Assert.Equal("category_mapping", logged.Operation);
            Assert.Equal("anthropic", logged.Provider);
            Assert.Equal("claude-sonnet-5", logged.Model);
            Assert.Equal(120, logged.InputTokens);
            Assert.Equal(45, logged.OutputTokens);
            Assert.Equal(30, logged.CacheReadTokens);
            Assert.Equal(8, logged.CacheCreationTokens);
            Assert.True(logged.DurationMs >= 0);
        }

        [Fact]
        public async Task ClaudeClient_RecordsAMissingCountAsNull_NotZero()
        {
            var repo = new Mock<IAiCallLogRepo>();
            LogAiCallInput? logged = null;
            repo.Setup(r => r.LogAsync(It.IsAny<LogAiCallInput>()))
                .Callback<LogAiCallInput>(i => logged = i)
                .ReturnsAsync(Guid.NewGuid());
            var sut = Claude(repo.Object, () => Json("""{"content":[{"type":"text","text":"{}"}],"usage":{"input_tokens":7}}"""));

            await sut.CompleteAsync("system", "user");

            Assert.Equal(7, logged!.InputTokens);
            Assert.Null(logged.OutputTokens);
            Assert.Null(logged.CacheReadTokens);
            Assert.Null(logged.CacheCreationTokens);
        }

        [Fact]
        public async Task ClaudeClient_StillReturnsTheText_WhenRecordingFails()
        {
            var repo = new Mock<IAiCallLogRepo>();
            repo.Setup(r => r.LogAsync(It.IsAny<LogAiCallInput>())).ThrowsAsync(new InvalidOperationException("db down"));
            var sut = Claude(repo.Object, () => Json(ClaudeOk));

            var text = await sut.CompleteAsync("system", "user");

            Assert.Equal("{}", text);
        }

        [Fact]
        public async Task ClaudeClient_RecordsNothing_WhenTheCallFails()
        {
            var repo = new Mock<IAiCallLogRepo>();
            var sut = Claude(repo.Object, () => new HttpResponseMessage(HttpStatusCode.Unauthorized) { Content = new StringContent("""{"type":"error"}""") });

            await Assert.ThrowsAsync<InvalidOperationException>(() => sut.CompleteAsync("system", "user"));

            repo.Verify(r => r.LogAsync(It.IsAny<LogAiCallInput>()), Times.Never);
        }

        [Fact]
        public async Task ClaudeClient_WorksWithoutARepository()
        {
            var sut = Claude(null, () => Json(ClaudeOk));

            Assert.Equal("{}", await sut.CompleteAsync("system", "user"));
        }

        [Fact]
        public async Task FoundryClient_AppendsPromptAndCompletionTokens_WithNoCacheCounts()
        {
            var repo = new Mock<IAiCallLogRepo>();
            LogAiCallInput? logged = null;
            repo.Setup(r => r.LogAsync(It.IsAny<LogAiCallInput>()))
                .Callback<LogAiCallInput>(i => logged = i)
                .ReturnsAsync(Guid.NewGuid());
            var sut = new AzureFoundryChatCompletionClient(
                FactoryReturning("AzureFoundry", "https://proj.services.ai.azure.com", () => Json(
                    """{"model":"gpt-4.1-mini","choices":[{"message":{"role":"assistant","content":"{}"}}],"usage":{"prompt_tokens":200,"completion_tokens":60}}""")),
                ConfigurationWith(("FOUNDRY_API_KEY", "key"), ("FOUNDRY_MODEL_DEPLOYMENT", "gpt-4.1-mini")),
                NullLogger<AzureFoundryChatCompletionClient>.Instance,
                repo.Object);

            using (AiCallContext.Begin(RequestId, null))
            using (AiUsageTelemetry.BeginOperation("document_extraction"))
            {
                await sut.CompleteAsync("system", "user");
            }

            Assert.Equal(RequestId, logged!.ChangeRequestId);
            Assert.Null(logged.AssessmentId);
            Assert.Equal("document_extraction", logged.Operation);
            Assert.Equal("az.ai.inference", logged.Provider);
            Assert.Equal(200, logged.InputTokens);
            Assert.Equal(60, logged.OutputTokens);
            Assert.Null(logged.CacheReadTokens);
        }

        [Fact]
        public void AiCallContext_NestsAndRestoresThePreviousIds()
        {
            Assert.Null(AiCallContext.ChangeRequestId);
            var inner = Guid.NewGuid();
            using (AiCallContext.Begin(RequestId, AssessmentId))
            {
                using (AiCallContext.Begin(inner, null))
                {
                    Assert.Equal(inner, AiCallContext.ChangeRequestId);
                    Assert.Null(AiCallContext.AssessmentId);
                }
                Assert.Equal(RequestId, AiCallContext.ChangeRequestId);
                Assert.Equal(AssessmentId, AiCallContext.AssessmentId);
            }
            Assert.Null(AiCallContext.ChangeRequestId);
        }

        private sealed class StubHandler(Func<HttpResponseMessage> respond) : HttpMessageHandler
        {
            protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
                Task.FromResult(respond());
        }
    }
}
