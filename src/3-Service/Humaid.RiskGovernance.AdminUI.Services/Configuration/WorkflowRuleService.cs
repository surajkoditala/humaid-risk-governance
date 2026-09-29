namespace Humaid.RiskGovernance.AdminUI.Services.Configuration
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Configuration;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Users;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Configuration;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Configuration;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core;

    public class WorkflowRuleService : IWorkflowRuleService
    {
        private readonly IWorkflowRuleRepo _workflowRuleRepo;
        private readonly IUserRepo _userRepo;

        public WorkflowRuleService(IWorkflowRuleRepo workflowRuleRepo, IUserRepo userRepo)
        {
            _workflowRuleRepo = workflowRuleRepo;
            _userRepo = userRepo;
        }

        public Task<IReadOnlyList<WorkflowRule>> GetAllAsync() => _workflowRuleRepo.GetAllActiveAsync();

        public async Task<Guid> UpsertAsync(UpsertWorkflowRuleInput input)
        {
            // DEF-002: same gap as scoring config - US-10.2 is scoped to an Analyst "with
            // configuration privileges", not any authenticated caller.
            var actorRole = await _userRepo.GetRoleAsync(input.ActorUserId);
            if (actorRole is not ("Analyst" or "Admin"))
            {
                throw new ValidationException("Only an FCRM Analyst may change a workflow rule.");
            }

            // US-10.2 AC2: reason mandatory - also enforced by func_upsertWorkflowRule, checked
            // here too so the API can return a clean 400 instead of a raw DB exception.
            if (string.IsNullOrWhiteSpace(input.Reason))
            {
                throw new ValidationException("A reason is required to change a workflow rule.");
            }
            return await _workflowRuleRepo.UpsertAsync(input);
        }
    }
}
