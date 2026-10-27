namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.AiUsage
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.AiUsage;

    /// <summary>Measured token use per change request. Read-only and informational: it never gates,
    /// scores or decides anything.</summary>
    public interface IAiUsageService
    {
        Task<AiUsageForRequest> GetForRequestAsync(Guid changeRequestId);
    }
}
