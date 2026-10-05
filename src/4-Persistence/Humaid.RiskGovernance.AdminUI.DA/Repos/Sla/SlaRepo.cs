namespace Humaid.RiskGovernance.AdminUI.DA.Repos.Sla
{
    using Dapper;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Sla;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Sla;

    public class SlaRepo : ISlaRepo
    {
        private readonly DapperConnectionFactory _connectionFactory;

        public SlaRepo(DapperConnectionFactory connectionFactory)
        {
            _connectionFactory = connectionFactory;
        }

        public async Task<SlaConfig?> GetConfigAsync()
        {
            await using var conn = await _connectionFactory.OpenAsync();
            return await conn.QuerySingleOrDefaultAsync<SlaConfig>("SELECT * FROM func_getSlaConfig()");
        }

        public async Task<IReadOnlyList<SlaTarget>> GetTargetsAsync()
        {
            await using var conn = await _connectionFactory.OpenAsync();
            var rows = await conn.QueryAsync<SlaTarget>("SELECT * FROM func_getSlaTargets()");
            return rows.AsList();
        }

        public async Task<IReadOnlyList<SlaHoliday>> GetHolidaysAsync()
        {
            await using var conn = await _connectionFactory.OpenAsync();
            // The date is read as text (yyyy-MM-dd) so it round-trips to the browser unchanged,
            // with no time-zone shift from a DateTime.
            var rows = await conn.QueryAsync<SlaHoliday>(
                "SELECT id, to_char(holiday_date, 'YYYY-MM-DD') AS holiday_date, reason, created_at FROM func_getSlaHolidays()");
            return rows.AsList();
        }

        public async Task<Guid> UpsertConfigAsync(string targetsJson, SaveSlaConfigInput input)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            return await conn.QuerySingleAsync<Guid>(
                "SELECT func_upsertSlaConfig(@targetsJson::jsonb, @AtRiskThresholdPct, @PauseOnClarification, @Retroactive, @Reason, @ActorUserId)",
                new
                {
                    targetsJson,
                    input.AtRiskThresholdPct,
                    input.PauseOnClarification,
                    input.Retroactive,
                    input.Reason,
                    input.ActorUserId,
                });
        }

        public async Task<Guid> AddHolidayAsync(AddSlaHolidayInput input)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            return await conn.QuerySingleAsync<Guid>(
                "SELECT func_addSlaHoliday(@HolidayDate::date, @Reason, @ActorUserId)", input);
        }

        public async Task RemoveHolidayAsync(Guid holidayId, RemoveSlaHolidayInput input)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            await conn.ExecuteAsync(
                "SELECT func_removeSlaHoliday(@holidayId, @Reason, @ActorUserId)",
                new { holidayId, input.Reason, input.ActorUserId });
        }

        public async Task<IReadOnlyList<SlaViewRow>> GetViewAsync(string? stage, string? changeType, string? state)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            var rows = await conn.QueryAsync<SlaViewRow>(
                "SELECT * FROM func_getSlaView(@stage, @changeType, @state)", new { stage, changeType, state });
            return rows.AsList();
        }

        public async Task<IReadOnlyList<SlaPerformanceRow>> GetPerformanceAsync(string? changeType)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            var rows = await conn.QueryAsync<SlaPerformanceRow>(
                "SELECT * FROM func_getSlaPerformance(@changeType)", new { changeType });
            return rows.AsList();
        }

        public async Task<IReadOnlyList<RequestSlaRow>> GetRequestSlaAsync(Guid changeRequestId)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            var rows = await conn.QueryAsync<RequestSlaRow>(
                "SELECT * FROM func_getRequestSla(@changeRequestId)", new { changeRequestId });
            return rows.AsList();
        }
    }
}
