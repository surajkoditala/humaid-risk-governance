namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Audit
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Audit;

    public interface IAuditRepo
    {
        Task<Guid> AppendAsync(AppendAuditEventInput input);
        Task<IReadOnlyList<AuditEvent>> GetTrailForRequestAsync(Guid changeRequestId);
    }
}
