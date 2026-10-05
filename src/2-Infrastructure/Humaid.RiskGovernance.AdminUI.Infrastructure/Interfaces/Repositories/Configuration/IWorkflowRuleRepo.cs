namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Configuration
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Configuration;

    public interface IWorkflowRuleRepo
    {
        Task<WorkflowRule?> GetActiveAsync(string ruleKey);
        Task<IReadOnlyList<WorkflowRule>> GetAllActiveAsync();
        Task<Guid> UpsertAsync(UpsertWorkflowRuleInput input);
    }
}
