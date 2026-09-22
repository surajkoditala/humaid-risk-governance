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
        private readonly IAuditExportService _auditExportService;

        public AuditController(IAuditService auditService, IAuditExportService auditExportService, ILogger<AuditController> logger)
            : base(logger)
        {
            _auditService = auditService;
            _auditExportService = auditExportService;
        }

        /// <summary>US-9.1: full chronological history for one change request.</summary>
        [HttpGet("{changeRequestId:guid}")]
        public Task<IActionResult> GetTrail(Guid changeRequestId) =>
            ExecuteAsync(async () =>
            {
                var trail = await _auditService.GetTrailAsync(changeRequestId);
                return OperationResult<IReadOnlyList<AuditEvent>>.Success(trail);
            }, "Failed to fetch audit trail.");

        /// <summary>US-9.3: the same trail as a durable, examiner-ready PDF.</summary>
        [HttpGet("{changeRequestId:guid}/Export")]
        public async Task<IActionResult> ExportPdf(Guid changeRequestId)
        {
            try
            {
                var pdfBytes = await _auditExportService.ExportPdfAsync(changeRequestId);
                if (pdfBytes is null)
                    return NotFound(OperationResult<object>.Failure($"Change request {changeRequestId} not found."));

                return File(pdfBytes, "application/pdf", $"audit-trail-{changeRequestId}.pdf");
            }
            catch (Exception ex)
            {
                Logger.LogError(ex, "Failed to export audit trail PDF for change request {ChangeRequestId}.", changeRequestId);
                return StatusCode(500, OperationResult<object>.Failure("Failed to export audit trail."));
            }
        }
    }
}
