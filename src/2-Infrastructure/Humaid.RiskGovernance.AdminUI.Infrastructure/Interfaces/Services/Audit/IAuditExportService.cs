namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Audit
{
    /// <summary>US-9.3: the full audit trail's own export path - US-9.1's AC names a "durable,
    /// human-readable format (e.g. PDF)" but no story owned building it until QA raised this gap.</summary>
    public interface IAuditExportService
    {
        Task<byte[]> ExportPdfAsync(Guid changeRequestId);
    }
}
