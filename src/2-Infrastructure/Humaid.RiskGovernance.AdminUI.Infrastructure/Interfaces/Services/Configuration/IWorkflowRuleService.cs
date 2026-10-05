namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Configuration
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Configuration;

    public interface IWorkflowRuleService
    {
        Task<IReadOnlyList<WorkflowRule>> GetAllAsync();

        /// <summary>US-10.2: reason mandatory - enforced by func_upsertWorkflowRule.</summary>
        Task<Guid> UpsertAsync(UpsertWorkflowRuleInput input);
    }
}
