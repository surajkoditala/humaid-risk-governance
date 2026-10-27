namespace Humaid.RiskGovernance.AdminUI.Services.AiUsage
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.AiUsage;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.AiUsage;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.AiUsage;

    /// <summary>
    /// Measured token use per change request: the recorded calls plus the totals. Pure arithmetic
    /// over what the provider reported - no AI, nothing estimated. A null count (not reported) adds
    /// nothing to a total, so a total can only under-report, never invent usage.
    /// </summary>
    public class AiUsageService : IAiUsageService
    {
        private readonly IAiCallLogRepo _aiCallLogRepo;

        public AiUsageService(IAiCallLogRepo aiCallLogRepo)
        {
            _aiCallLogRepo = aiCallLogRepo;
        }

        public async Task<AiUsageForRequest> GetForRequestAsync(Guid changeRequestId)
        {
            var calls = await _aiCallLogRepo.GetForRequestAsync(changeRequestId);
            return Summarize(calls);
        }

        public static AiUsageForRequest Summarize(IReadOnlyList<AiCall> calls) => new()
        {
            Calls = calls,
            CallCount = calls.Count,
            InputTokens = calls.Sum(c => c.InputTokens ?? 0),
            OutputTokens = calls.Sum(c => c.OutputTokens ?? 0),
            CacheReadTokens = calls.Sum(c => c.CacheReadTokens ?? 0),
            CacheCreationTokens = calls.Sum(c => c.CacheCreationTokens ?? 0),
            ByOperation = calls
                .GroupBy(c => c.Operation)
                .Select(g => new AiUsageByOperation
                {
                    Operation = g.Key,
                    Calls = g.Count(),
                    InputTokens = g.Sum(c => c.InputTokens ?? 0),
                    OutputTokens = g.Sum(c => c.OutputTokens ?? 0),
                })
                .OrderBy(o => o.Operation, StringComparer.Ordinal)
                .ToList(),
        };
    }
}
