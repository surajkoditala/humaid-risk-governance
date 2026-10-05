namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Sla
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core;

    /// <summary>Epic 19 - the workflow stages an SLA is measured against. <c>EndToEnd</c> is
    /// submission to committee decision. See schema/015_sla.sql.</summary>
    public static class SlaStages
    {
        public const string Submitted = "Submitted";
        public const string InAssessment = "InAssessment";
        public const string PendingCommittee = "PendingCommittee";
        public const string EndToEnd = "EndToEnd";

        public static readonly IReadOnlyList<string> All = [Submitted, InAssessment, PendingCommittee, EndToEnd];
        public static readonly IReadOnlyList<string> StageOnly = [Submitted, InAssessment, PendingCommittee];
    }

    /// <summary>US-19.1 - the active SLA version's settings.</summary>
    public class SlaConfig
    {
        public Guid Id { get; set; }
        public int VersionNumber { get; set; }

        /// <summary>1-99: the percentage of a target after which a request is "At risk".</summary>
        public int AtRiskThresholdPct { get; set; }

        /// <summary>When true, days spent waiting on the Product Owner are not charged to the analyst stage.</summary>
        public bool PauseOnClarification { get; set; }
        public string Reason { get; set; } = string.Empty;
        public DateTimeOffset CreatedAt { get; set; }
    }

    /// <summary>A target in business days for one change type at one stage.</summary>
    public class SlaTarget
    {
        public string ChangeType { get; set; } = string.Empty;

        /// <summary>Submitted | InAssessment | PendingCommittee | EndToEnd.</summary>
        public string Stage { get; set; } = string.Empty;
        public int TargetBusinessDays { get; set; }
    }

    public class SlaHoliday
    {
        public Guid Id { get; set; }

        /// <summary>yyyy-MM-dd.</summary>
        public string HolidayDate { get; set; } = string.Empty;
        public string Reason { get; set; } = string.Empty;
        public DateTimeOffset CreatedAt { get; set; }
    }

    /// <summary>Everything the Configuration screen needs in one round trip.</summary>
    public class SlaConfigView
    {
        public SlaConfig? Config { get; set; }
        public IReadOnlyList<SlaTarget> Targets { get; set; } = [];
        public IReadOnlyList<SlaHoliday> Holidays { get; set; } = [];
    }

    public class SaveSlaConfigInput
    {
        public List<SlaTarget> Targets { get; set; } = [];
        public int AtRiskThresholdPct { get; set; }
        public bool PauseOnClarification { get; set; } = true;

        /// <summary>Also move requests already in flight onto this version (US-19.1 AC7).</summary>
        public bool Retroactive { get; set; }

        /// <summary>The caller has seen the warnings returned by a previous save attempt and accepts them (US-19.1 AC4).</summary>
        public bool ConfirmWarnings { get; set; }
        public string Reason { get; set; } = string.Empty;
        public Guid ActorUserId { get; set; }
    }

    public class SaveSlaConfigResult
    {
        /// <summary>False when warnings must be confirmed first - nothing was written.</summary>
        public bool Saved { get; set; }
        public Guid? ConfigId { get; set; }
        public IReadOnlyList<string> Warnings { get; set; } = [];
    }

    public class AddSlaHolidayInput
    {
        /// <summary>yyyy-MM-dd.</summary>
        public string HolidayDate { get; set; } = string.Empty;
        public string Reason { get; set; } = string.Empty;
        public Guid ActorUserId { get; set; }
    }

    public class RemoveSlaHolidayInput
    {
        public string Reason { get; set; } = string.Empty;
        public Guid ActorUserId { get; set; }
    }

    /// <summary>
    /// US-19.5 AC1 - the SLA grid's paging / sorting / filtering, on top of the shared grid contract.
    /// Search matches title and request number; <see cref="GridQuery.SortBy"/> is one of requestNumber,
    /// title, changeType, stage, progress or dueAt (blank = most urgent first). The shared
    /// <c>Status</c> filter is not used here - SLA state is <see cref="State"/>.
    /// </summary>
    public class SlaViewQuery : GridQuery
    {
        /// <summary>The acting user - the server checks they may see SLA reporting.</summary>
        public Guid ActorUserId { get; set; }

        /// <summary>Submitted | InAssessment | PendingCommittee.</summary>
        public string? Stage { get; set; }

        /// <summary>OnTrack | AtRisk | Breached.</summary>
        public string? State { get; set; }
    }

    /// <summary>How many open requests are in one SLA state (null state = no target configured).</summary>
    public class SlaStateCount
    {
        public string? OverallState { get; set; }
        public int RequestCount { get; set; }
    }

    /// <summary>US-19.5 AC1 - one open request and where it stands against its SLA.</summary>
    public class SlaViewRow
    {
        public Guid ChangeRequestId { get; set; }
        public string RequestNumber { get; set; } = string.Empty;
        public string Title { get; set; } = string.Empty;
        public string ChangeType { get; set; } = string.Empty;
        public string Stage { get; set; } = string.Empty;
        public DateTimeOffset EnteredAt { get; set; }
        public int? TargetDays { get; set; }
        public int ElapsedDays { get; set; }
        public int WaitingDays { get; set; }
        public DateTimeOffset? DueAt { get; set; }

        /// <summary>OnTrack | AtRisk | Breached, null when no target is configured.</summary>
        public string? StageState { get; set; }
        public DateTimeOffset? E2eDueAt { get; set; }
        public string? E2eState { get; set; }

        /// <summary>The worse of the stage and end-to-end states.</summary>
        public string? OverallState { get; set; }
        public int DaysOverdue { get; set; }
    }

    /// <summary>US-19.5 AC2/AC3 - cycle time of finished stages / decided requests against target.
    /// <see cref="ChangeType"/> is "All" for the combined end-to-end row.</summary>
    public class SlaPerformanceRow
    {
        public string ChangeType { get; set; } = string.Empty;
        public string Stage { get; set; } = string.Empty;
        public int SampleCount { get; set; }
        public int? TargetDays { get; set; }
        public decimal? MedianDays { get; set; }
        public decimal? P90Days { get; set; }

        /// <summary>Percentage of finished requests that met their SLA, 0-100.</summary>
        public decimal? MetPercent { get; set; }
    }

    /// <summary>US-19.2 - one request's SLA picture. Scope is Stage (live), EndToEnd, or Completed (frozen).</summary>
    public class RequestSlaRow
    {
        public string Scope { get; set; } = string.Empty;
        public string? Stage { get; set; }
        public DateTimeOffset? EnteredAt { get; set; }
        public DateTimeOffset? LeftAt { get; set; }
        public int? TargetDays { get; set; }
        public int? ElapsedDays { get; set; }

        /// <summary>Time waiting on the Product Owner - shown separately, not charged to the analyst stage.</summary>
        public int? WaitingDays { get; set; }
        public DateTimeOffset? DueAt { get; set; }

        /// <summary>OnTrack | AtRisk | Breached while open; Met | Missed once a stage or the request is done.</summary>
        public string? State { get; set; }
    }
}
