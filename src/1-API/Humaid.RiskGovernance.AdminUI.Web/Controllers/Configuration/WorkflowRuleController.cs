namespace Humaid.RiskGovernance.AdminUI.Web.Controllers.Configuration
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Configuration;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Configuration;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core;
    using Humaid.RiskGovernance.AdminUI.Web.Controllers.Core;
    using Microsoft.AspNetCore.Authorization;
    using Microsoft.AspNetCore.Mvc;

    /// <summary>Epic 10 (workflow-rule half) - Platform Configuration, analyst-owned.</summary>
    [Authorize]
    [Route("api/[controller]")]
    public class WorkflowRuleController : BaseApiController
    {
        private readonly IWorkflowRuleService _workflowRuleService;

        public WorkflowRuleController(IWorkflowRuleService workflowRuleService, ILogger<WorkflowRuleController> logger)
            : base(logger)
        {
            _workflowRuleService = workflowRuleService;
        }

        /// <summary>US-10.2 AC1: current rules in plain, structured form.</summary>
        [HttpGet]
        public Task<IActionResult> GetAll() =>
            ExecuteAsync(async () =>
            {
                var rules = await _workflowRuleService.GetAllAsync();
                return OperationResult<IReadOnlyList<WorkflowRule>>.Success(rules);
            }, "Failed to fetch workflow rules.");

        /// <summary>US-10.2 AC2: reason mandatory; a new versioned row, never an in-place update.</summary>
        [HttpPost]
        public Task<IActionResult> Upsert([FromBody] UpsertWorkflowRuleInput input) =>
            ExecuteAsync(async () =>
            {
                try
                {
                    var id = await _workflowRuleService.UpsertAsync(input);
                    return OperationResult<Guid>.Success(id);
                }
                catch (InvalidOperationException ex)
                {
                    return OperationResult<Guid>.BadRequest(ex.Message);
                }
            }, "Failed to update workflow rule.");
    }
}
