namespace Humaid.RiskGovernance.AdminUI.AI
{
    using System.Diagnostics;
    using System.Diagnostics.Metrics;
    using Microsoft.Extensions.Logging;

    /// <summary>
    /// Measured token use: the provider-reported token counts for every successful AI call, as an
    /// OpenTelemetry metric (<c>gen_ai.client.token.usage</c>, the GenAI semantic-convention name)
    /// plus one structured log line. With Application Insights enabled (Program.cs registers this
    /// meter) the metric lands in the <c>AppMetrics</c> table, so tokens per step, per model and
    /// per day are a query away - see the "Workbench AI monitoring" workbook.
    /// <para>
    /// The counts are exactly what Anthropic / Azure AI Foundry report and bill on - nothing is
    /// estimated locally. A call that fails (401, 404, 5xx) carries no usage and records nothing.
    /// </para>
    /// <para>
    /// Which step made the call is carried by an ambient scope (<see cref="BeginOperation"/>) set
    /// by each AI-touchpoint client, so the provider clients and
    /// <c>IChatCompletionClient.CompleteAsync</c> keep their existing signatures.
    /// </para>
    /// </summary>
    public static class AiUsageTelemetry
    {
        public const string MeterName = "Humaid.RiskGovernance.AI";

        private static readonly Meter Meter = new(MeterName);

        private static readonly Histogram<long> TokenUsage = Meter.CreateHistogram<long>(
            "gen_ai.client.token.usage",
            unit: "{token}",
            description: "Tokens reported by the AI provider per call, split by token type (input, output, cache_read, cache_creation).");

        private static readonly AsyncLocal<string?> CurrentOperation = new();

        /// <summary>The step the current async flow is running for, or "unspecified".</summary>
        public static string Operation => CurrentOperation.Value ?? "unspecified";

        /// <summary>
        /// Tags every AI call made inside the returned scope with <paramref name="operation"/>
        /// (e.g. "category_mapping"). Disposing restores whatever was set before, so scopes nest.
        /// </summary>
        public static IDisposable BeginOperation(string operation)
        {
            var previous = CurrentOperation.Value;
            CurrentOperation.Value = operation;
            return new Scope(previous);
        }

        /// <summary>
        /// Records one call's usage. A null count (the provider did not report it) is skipped, not
        /// recorded as zero, so a missing field can never look like a free call.
        /// </summary>
        public static void Record(
            ILogger logger,
            string provider,
            string? model,
            long? inputTokens,
            long? outputTokens,
            long? cacheReadTokens = null,
            long? cacheCreationTokens = null)
        {
            var operation = Operation;
            RecordType("input", inputTokens);
            RecordType("output", outputTokens);
            RecordType("cache_read", cacheReadTokens);
            RecordType("cache_creation", cacheCreationTokens);

            logger.LogInformation(
                "AI usage: {Operation} via {Provider}/{Model} - {InputTokens} input, {OutputTokens} output tokens (cache read {CacheReadTokens}, cache write {CacheCreationTokens})",
                operation, provider, model ?? "(unknown)", inputTokens, outputTokens, cacheReadTokens ?? 0, cacheCreationTokens ?? 0);

            void RecordType(string tokenType, long? count)
            {
                if (count is null)
                {
                    return;
                }
                TokenUsage.Record(
                    count.Value,
                    new KeyValuePair<string, object?>("gen_ai.token.type", tokenType),
                    new KeyValuePair<string, object?>("gen_ai.system", provider),
                    new KeyValuePair<string, object?>("gen_ai.request.model", model ?? "(unknown)"),
                    new KeyValuePair<string, object?>("humaid.ai.operation", operation));
            }
        }

        private sealed class Scope(string? previous) : IDisposable
        {
            public void Dispose() => CurrentOperation.Value = previous;
        }
    }
}
