namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.AiUsage
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.AiUsage;

    public interface IAiCallLogRepo
    {
        /// <summary>Appends one ai_call_log row. There is deliberately no update or delete.</summary>
        Task<Guid> LogAsync(LogAiCallInput input);

        Task<IReadOnlyList<AiCall>> GetForRequestAsync(Guid changeRequestId);
    }
}
