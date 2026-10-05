namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Sla
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Sla;

    public interface ISlaRepo
    {
        Task<SlaConfig?> GetConfigAsync();
        Task<IReadOnlyList<SlaTarget>> GetTargetsAsync();
        Task<IReadOnlyList<SlaHoliday>> GetHolidaysAsync();

        /// <summary>Saves a new SLA version. <paramref name="targetsJson"/> is the 24-entry list
        /// func_upsertSlaConfig expects (changeType / stage / targetBusinessDays).</summary>
        Task<Guid> UpsertConfigAsync(string targetsJson, SaveSlaConfigInput input);
        Task<Guid> AddHolidayAsync(AddSlaHolidayInput input);
        Task RemoveHolidayAsync(Guid holidayId, RemoveSlaHolidayInput input);

        Task<IReadOnlyList<SlaViewRow>> GetViewAsync(string? stage, string? changeType, string? state);
        Task<IReadOnlyList<SlaPerformanceRow>> GetPerformanceAsync(string? changeType);
        Task<IReadOnlyList<RequestSlaRow>> GetRequestSlaAsync(Guid changeRequestId);
    }
}
