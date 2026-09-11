namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Configuration
{
    /// <summary>Epic 10 (workflow-rule half) - a versioned platform configuration value, e.g.
    /// "CommitteeQuorum". See schema/012_configuration.sql.</summary>
    public class WorkflowRule
    {
        public Guid Id { get; set; }
        public string RuleKey { get; set; } = string.Empty;
        public string RuleValueJson { get; set; } = "{}";
        public bool IsActive { get; set; }
        public DateTimeOffset CreatedAt { get; set; }
    }

    public class UpsertWorkflowRuleInput
    {
        public string RuleKey { get; set; } = string.Empty;
        public string RuleValueJson { get; set; } = "{}";
        public string Reason { get; set; } = string.Empty;
        public Guid ActorUserId { get; set; }
    }
}
