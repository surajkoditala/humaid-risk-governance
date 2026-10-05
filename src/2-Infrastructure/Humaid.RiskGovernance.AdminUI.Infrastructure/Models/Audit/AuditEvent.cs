namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Audit
{
    /// <summary>Epic 9 - one append-only audit_event row. See schema/013_audit.sql.</summary>
    public class AuditEvent
    {
        public Guid Id { get; set; }
        public string EntityType { get; set; } = string.Empty;
        public Guid? EntityId { get; set; }
        public string Action { get; set; } = string.Empty;
        public Guid? ActorUserId { get; set; }
        public string? ActorName { get; set; }

        /// <summary>'human' or 'system/AI'.</summary>
        public string ActorLabel { get; set; } = string.Empty;
        public string? BeforeValueJson { get; set; }
        public string? AfterValueJson { get; set; }
        public string? Reason { get; set; }
        public DateTimeOffset CreatedAt { get; set; }
    }

    public class AppendAuditEventInput
    {
        public Guid? ChangeRequestId { get; set; }
        public Guid? AssessmentId { get; set; }
        public string EntityType { get; set; } = string.Empty;
        public Guid? EntityId { get; set; }
        public string Action { get; set; } = string.Empty;
        public Guid? ActorUserId { get; set; }
        public string ActorLabel { get; set; } = "system/AI";
        public string? BeforeValueJson { get; set; }
        public string? AfterValueJson { get; set; }
        public string? Reason { get; set; }
    }
}
