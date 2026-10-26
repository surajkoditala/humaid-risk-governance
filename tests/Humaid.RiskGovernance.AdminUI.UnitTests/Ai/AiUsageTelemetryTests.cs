namespace Humaid.RiskGovernance.AdminUI.UnitTests.Ai
{
    using System.Diagnostics.Metrics;
    using System.Net;
    using System.Text;
    using Humaid.RiskGovernance.AdminUI.AI;
    using Microsoft.Extensions.Configuration;
    using Microsoft.Extensions.Logging.Abstractions;
    using Moq;
    using Xunit;

    /// <summary>
    /// Measured token use: the counts the providers report must reach the gen_ai.client.token.usage
    /// metric, tagged with the step that made the call, and a missing count must never be recorded
    /// as zero (a missing field must not look like a free call). Each test tags its calls with a
    /// unique operation name so measurements from other tests running in parallel in this process
    /// cannot leak in - the meter is process-global.
    /// </summary>
    public class AiUsageTelemetryTests
    {
        private sealed record Measurement(long Value, string TokenType, string System, string Model, string Operation);

        /// <summary>Collects gen_ai.client.token.usage measurements for one operation name.</summary>
        private sealed class Collector : IDisposable
        {
            private readonly MeterListener _listener = new();
            private readonly string _operation;
            private readonly object _gate = new();
            public List<Measurement> Measurements { get; } = [];

            public Collector(string operation)
            {
                _operation = operation;
                _listener.InstrumentPublished = (instrument, listener) =>
                {
                    if (instrument.Meter.Name == AiUsageTelemetry.MeterName && instrument.Name == "gen_ai.client.token.usage")
                    {
                        listener.EnableMeasurementEvents(instrument);
                    }
                };
                _listener.SetMeasurementEventCallback<long>((_, value, tags, _) =>
                {
                    var tagArray = tags.ToArray();
                    string Tag(string name) => tagArray.FirstOrDefault(t => t.Key == name).Value?.ToString() ?? "";
                    if (Tag("humaid.ai.operation") != _operation)
                    {
                        return;
                    }
                    lock (_gate)
                    {
                        Measurements.Add(new Measurement(value, Tag("gen_ai.token.type"), Tag("gen_ai.system"), Tag("gen_ai.request.model"), _operation));
                    }
                });
                _listener.Start();
            }

            public void Dispose() => _listener.Dispose();
        }

        private static string UniqueOperation() => "test-" + Guid.NewGuid().ToString("N");

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

        [Fact]
        public async Task ClaudeClient_RecordsReportedUsage_TaggedWithTheCurrentStep()
        {
            var operation = UniqueOperation();
            using var collector = new Collector(operation);
            var factory = FactoryReturning("AnthropicApi", "https://api.anthropic.com", () => Json(
                """{"model":"claude-sonnet-5","content":[{"type":"text","text":"{}"}],"usage":{"input_tokens":120,"output_tokens":45,"cache_read_input_tokens":30,"cache_creation_input_tokens":8}}"""));
            var sut = new ClaudeApiClient(
                factory,
                ConfigurationWith(("ANTHROPIC_API_KEY", "sk-ant-api03-abc123"), ("ANTHROPIC_MODEL", "claude-sonnet-5")),
                NullLogger<ClaudeApiClient>.Instance);

            using (AiUsageTelemetry.BeginOperation(operation))
            {
                await sut.CompleteAsync("system", "user");
            }

            Assert.Equal(
                [("input", 120L), ("output", 45L), ("cache_read", 30L), ("cache_creation", 8L)],
                collector.Measurements.Select(m => (m.TokenType, m.Value)).ToArray());
            Assert.All(collector.Measurements, m =>
            {
                Assert.Equal("anthropic", m.System);
                Assert.Equal("claude-sonnet-5", m.Model);
            });
        }

        [Fact]
        public async Task ClaudeClient_DoesNotRecordAMissingCountAsZero()
        {
            var operation = UniqueOperation();
            using var collector = new Collector(operation);
            var factory = FactoryReturning("AnthropicApi", "https://api.anthropic.com", () => Json(
                """{"content":[{"type":"text","text":"{}"}],"usage":{"input_tokens":7}}"""));
            var sut = new ClaudeApiClient(
                factory,
                ConfigurationWith(("ANTHROPIC_API_KEY", "sk-ant-api03-abc123"), ("ANTHROPIC_MODEL", "claude-sonnet-5")),
                NullLogger<ClaudeApiClient>.Instance);

            using (AiUsageTelemetry.BeginOperation(operation))
            {
                await sut.CompleteAsync("system", "user");
            }

            var only = Assert.Single(collector.Measurements);
            Assert.Equal(("input", 7L), (only.TokenType, only.Value));
            // No "model" in the response: falls back to the configured model rather than dropping the tag.
            Assert.Equal("claude-sonnet-5", only.Model);
        }

        [Fact]
        public async Task ClaudeClient_RecordsNothing_WhenTheCallFails()
        {
            var operation = UniqueOperation();
            using var collector = new Collector(operation);
            var factory = FactoryReturning("AnthropicApi", "https://api.anthropic.com", () =>
                new HttpResponseMessage(HttpStatusCode.Unauthorized) { Content = new StringContent("""{"type":"error"}""") });
            var sut = new ClaudeApiClient(
                factory,
                ConfigurationWith(("ANTHROPIC_API_KEY", "sk-ant-api03-abc123"), ("ANTHROPIC_MODEL", "claude-sonnet-5")),
                NullLogger<ClaudeApiClient>.Instance);

            using (AiUsageTelemetry.BeginOperation(operation))
            {
                await Assert.ThrowsAsync<InvalidOperationException>(() => sut.CompleteAsync("system", "user"));
            }

            Assert.Empty(collector.Measurements);
        }

        [Fact]
        public async Task FoundryClient_RecordsPromptAndCompletionTokens()
        {
            var operation = UniqueOperation();
            using var collector = new Collector(operation);
            var factory = FactoryReturning("AzureFoundry", "https://proj.services.ai.azure.com", () => Json(
                """{"model":"gpt-4.1-mini","choices":[{"message":{"role":"assistant","content":"{}"}}],"usage":{"prompt_tokens":200,"completion_tokens":60,"total_tokens":260}}"""));
            var sut = new AzureFoundryChatCompletionClient(
                factory,
                ConfigurationWith(("FOUNDRY_API_KEY", "key"), ("FOUNDRY_MODEL_DEPLOYMENT", "gpt-4.1-mini")),
                NullLogger<AzureFoundryChatCompletionClient>.Instance);

            using (AiUsageTelemetry.BeginOperation(operation))
            {
                await sut.CompleteAsync("system", "user");
            }

            Assert.Equal(
                [("input", 200L), ("output", 60L)],
                collector.Measurements.Select(m => (m.TokenType, m.Value)).ToArray());
            Assert.All(collector.Measurements, m =>
            {
                Assert.Equal("az.ai.inference", m.System);
                Assert.Equal("gpt-4.1-mini", m.Model);
            });
        }

        [Fact]
        public void BeginOperation_NestsAndRestoresThePreviousStep()
        {
            Assert.Equal("unspecified", AiUsageTelemetry.Operation);
            using (AiUsageTelemetry.BeginOperation("outer"))
            {
                using (AiUsageTelemetry.BeginOperation("inner"))
                {
                    Assert.Equal("inner", AiUsageTelemetry.Operation);
                }
                Assert.Equal("outer", AiUsageTelemetry.Operation);
            }
            Assert.Equal("unspecified", AiUsageTelemetry.Operation);
        }

        private sealed class StubHandler(Func<HttpResponseMessage> respond) : HttpMessageHandler
        {
            protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
                Task.FromResult(respond());
        }
    }
}
