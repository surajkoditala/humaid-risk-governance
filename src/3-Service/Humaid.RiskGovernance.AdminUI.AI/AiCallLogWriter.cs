namespace Humaid.RiskGovernance.AdminUI.AI
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Ai;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.AiUsage;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.AiUsage;
    using Microsoft.Extensions.Logging;

    /// <summary>
    /// Measured token use per change request: appends one ai_call_log row for a successful AI call,
    /// tagged with the request the calling service established (<see cref="AiCallContext"/>) and the
    /// step the touchpoint client established (<see cref="AiUsageTelemetry.BeginOperation"/>).
    /// <para>
    /// Best-effort by design. Recording usage is informational, so a database problem must never
    /// fail the AI call the analyst is waiting on: the write is caught and logged, and the AI step
    /// carries on. With no repository (the evals console app, local runs without a database) it
    /// does nothing.
    /// </para>
    /// </summary>
    internal static class AiCallLogWriter
    {
        public static async Task TryWriteAsync(
            IAiCallLogRepo? repo,
            ILogger logger,
            string provider,
            string? model,
            long? inputTokens,
            long? outputTokens,
            long? cacheReadTokens,
            long? cacheCreationTokens,
            int durationMs)
        {
            if (repo is null)
            {
                return;
            }

            try
            {
                await repo.LogAsync(new LogAiCallInput
                {
                    ChangeRequestId = AiCallContext.ChangeRequestId,
                    AssessmentId = AiCallContext.AssessmentId,
                    Operation = AiUsageTelemetry.Operation,
                    Provider = provider,
                    Model = model,
                    InputTokens = inputTokens,
                    OutputTokens = outputTokens,
                    CacheReadTokens = cacheReadTokens,
                    CacheCreationTokens = cacheCreationTokens,
                    DurationMs = durationMs,
                });
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Could not record AI token usage for {Operation}; the AI call itself is unaffected.", AiUsageTelemetry.Operation);
            }
        }
    }
}
