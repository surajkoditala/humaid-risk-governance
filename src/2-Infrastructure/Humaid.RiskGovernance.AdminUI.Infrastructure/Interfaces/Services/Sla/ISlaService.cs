namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Sla
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Sla;

    /// <summary>
    /// Epic 19 - SLA tracking. Everything here is deterministic arithmetic over recorded timestamps
    /// (no AI), and an SLA state only informs: nothing in this service changes a request's status or
    /// decides anything.
    /// </summary>
    public interface ISlaService
    {
        Task<SlaConfigView> GetConfigAsync(Guid actorUserId);

        /// <summary>US-19.1: Admin only; reason mandatory; refused (nothing written) on a bad target;
        /// returns warnings without saving when stage targets exceed the end-to-end target and the
        /// caller has not confirmed.</summary>
        Task<SaveSlaConfigResult> SaveConfigAsync(SaveSlaConfigInput input);
        Task<Guid> AddHolidayAsync(AddSlaHolidayInput input);
        Task RemoveHolidayAsync(Guid holidayId, RemoveSlaHolidayInput input);

        /// <summary>US-19.5: Analyst or Admin only - a Product Owner sees just their own due date
        /// and state through the request list.</summary>
        Task<PagedResult<SlaViewRow>> GetViewAsync(SlaViewQuery query);

        /// <summary>Counts per SLA state for the same stage / type / search filters (not the state filter).</summary>
        Task<IReadOnlyList<SlaStateCount>> GetSummaryAsync(SlaViewQuery query);
        Task<IReadOnlyList<SlaPerformanceRow>> GetPerformanceAsync(Guid actorUserId, string? changeType);
        Task<IReadOnlyList<RequestSlaRow>> GetRequestSlaAsync(Guid actorUserId, Guid changeRequestId);
    }
}
