namespace Humaid.RiskGovernance.AdminUI.Services.Configuration
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Configuration;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Configuration;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Configuration;

    public class WorkflowRuleService : IWorkflowRuleService
    {
        private readonly IWorkflowRuleRepo _workflowRuleRepo;

        public WorkflowRuleService(IWorkflowRuleRepo workflowRuleRepo)
        {
            _workflowRuleRepo = workflowRuleRepo;
        }

        public Task<IReadOnlyList<WorkflowRule>> GetAllAsync() => _workflowRuleRepo.GetAllActiveAsync();

        public Task<Guid> UpsertAsync(UpsertWorkflowRuleInput input)
        {
            // US-10.2 AC2: reason mandatory - also enforced by func_upsertWorkflowRule, checked
            // here too so the API can return a clean 400 instead of a raw DB exception.
            if (string.IsNullOrWhiteSpace(input.Reason))
            {
                throw new InvalidOperationException("A reason is required to change a workflow rule.");
            }
            return _workflowRuleRepo.UpsertAsync(input);
        }
    }
}
