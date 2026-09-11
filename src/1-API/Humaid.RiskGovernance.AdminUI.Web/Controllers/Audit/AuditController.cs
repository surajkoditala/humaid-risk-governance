namespace Humaid.RiskGovernance.AdminUI.Web.Controllers.Audit
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Audit;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Audit;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core;
    using Humaid.RiskGovernance.AdminUI.Web.Controllers.Core;
    using Microsoft.AspNetCore.Authorization;
    using Microsoft.AspNetCore.Mvc;

    /// <summary>Epic 9 - Immutable Audit Trail. Read-only by design - there is deliberately no
    /// write endpoint here beyond what other modules' own stored functions already append.</summary>
    [Authorize]
    [Route("api/[controller]")]
    public class AuditController : BaseApiController
    {
        private readonly IAuditService _auditService;

        public AuditController(IAuditService auditService, ILogger<AuditController> logger)
            : base(logger)
        {
            _auditService = auditService;
        }

        /// <summary>US-9.1: full chronological history for one change request.</summary>
        [HttpGet("{changeRequestId:guid}")]
        public Task<IActionResult> GetTrail(Guid changeRequestId) =>
            ExecuteAsync(async () =>
            {
                var trail = await _auditService.GetTrailAsync(changeRequestId);
                return OperationResult<IReadOnlyList<AuditEvent>>.Success(trail);
            }, "Failed to fetch audit trail.");
    }
}
