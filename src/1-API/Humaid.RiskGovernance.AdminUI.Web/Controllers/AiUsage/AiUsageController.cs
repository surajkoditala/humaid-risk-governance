namespace Humaid.RiskGovernance.AdminUI.Web.Controllers.AiUsage
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.AiUsage;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.AiUsage;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Users;
    using Humaid.RiskGovernance.AdminUI.Web.Controllers.Core;
    using Microsoft.AspNetCore.Authorization;
    using Microsoft.AspNetCore.Mvc;

    /// <summary>
    /// Measured token use per change request: the AI calls made for it and the tokens the provider
    /// reported. Read-only and informational. Same audience as the audit trail (Analyst, Admin): it
    /// is operational detail about how an assessment was prepared, not something a Product Owner or
    /// committee member needs. There is deliberately no write endpoint - rows are appended by the AI
    /// clients themselves as they make calls.
    /// </summary>
    [Authorize(Roles = AppRoles.AnalystOrAdmin)]
    [Route("api/[controller]")]
    public class AiUsageController : BaseApiController
    {
        private readonly IAiUsageService _aiUsageService;

        public AiUsageController(IAiUsageService aiUsageService, ILogger<AiUsageController> logger)
            : base(logger)
        {
            _aiUsageService = aiUsageService;
        }

        [HttpGet("{changeRequestId:guid}")]
        public Task<IActionResult> GetForRequest(Guid changeRequestId) =>
            ExecuteAsync(async () =>
            {
                var usage = await _aiUsageService.GetForRequestAsync(changeRequestId);
                return OperationResult<AiUsageForRequest>.Success(usage);
            }, "Failed to fetch AI usage.");
    }
}
