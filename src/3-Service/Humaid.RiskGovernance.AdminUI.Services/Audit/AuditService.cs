namespace Humaid.RiskGovernance.AdminUI.Services.Audit
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Audit;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Audit;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Audit;

    public class AuditService : IAuditService
    {
        private readonly IAuditRepo _auditRepo;

        public AuditService(IAuditRepo auditRepo)
        {
            _auditRepo = auditRepo;
        }

        public async Task LogAsync(AppendAuditEventInput input) => await _auditRepo.AppendAsync(input);

        public async Task<IReadOnlyList<AuditEvent>> GetTrailAsync(Guid changeRequestId) =>
            await _auditRepo.GetTrailForRequestAsync(changeRequestId);
    }
}
