namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Audit
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Audit;

    /// <summary>The one shared, cross-cutting service every other module can call into. Most
    /// module-specific writes already log their own audit_event inside their stored function (see
    /// docs/architecture/architecture-mapping.md) - this is for reads, and for events not already
    /// covered by a domain-specific function.</summary>
    public interface IAuditService
    {
        Task LogAsync(AppendAuditEventInput input);

        /// <summary>US-9.1: full chronological history for one change request.</summary>
        Task<IReadOnlyList<AuditEvent>> GetTrailAsync(Guid changeRequestId);
    }
}
