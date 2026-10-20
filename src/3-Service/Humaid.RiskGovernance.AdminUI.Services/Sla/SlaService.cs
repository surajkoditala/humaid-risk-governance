namespace Humaid.RiskGovernance.AdminUI.Services.Sla
{
    using System.Globalization;
    using System.Text.Json;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Sla;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Users;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Sla;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Sla;

    /// <summary>
    /// Epic 19 (US-19.1, US-19.2, US-19.5). Deterministic arithmetic over recorded timestamps - no AI
    /// involved anywhere. The numbers themselves (due dates, elapsed days, SLA state) are computed in
    /// the database from recorded stage timestamps; this service owns who may change or see them and
    /// refuses a bad configuration before anything is written.
    /// </summary>
    public class SlaService : ISlaService
    {
        private static readonly string[] ChangeTypes = ["Product", "Feature", "Process", "Vendor", "Geography", "CustomerSegment"];
        private static readonly JsonSerializerOptions CamelCase = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };

        private readonly ISlaRepo _slaRepo;
        private readonly IUserRepo _userRepo;

        public SlaService(ISlaRepo slaRepo, IUserRepo userRepo)
        {
            _slaRepo = slaRepo;
            _userRepo = userRepo;
        }

        public async Task<SlaConfigView> GetConfigAsync(Guid actorUserId)
        {
            await RequireRoleAsync(actorUserId, "view the SLA configuration", "Analyst", "Admin");
            return new SlaConfigView
            {
                Config = await _slaRepo.GetConfigAsync(),
                Targets = await _slaRepo.GetTargetsAsync(),
                Holidays = await _slaRepo.GetHolidaysAsync(),
            };
        }

        public async Task<SaveSlaConfigResult> SaveConfigAsync(SaveSlaConfigInput input)
        {
            await RequireRoleAsync(input.ActorUserId, "change the SLA configuration", "Admin");

            if (string.IsNullOrWhiteSpace(input.Reason))
            {
                throw new ValidationException("A reason is required to change the SLA configuration.");
            }
            if (input.AtRiskThresholdPct is < 1 or > 99)
            {
                throw new ValidationException("The at-risk warning threshold must be a whole number between 1 and 99 (percent of the target).");
            }

            var targets = ValidateTargets(input.Targets);

            var warnings = FindInconsistencies(targets);
            if (warnings.Count > 0 && !input.ConfirmWarnings)
            {
                return new SaveSlaConfigResult { Saved = false, Warnings = warnings };
            }

            var json = JsonSerializer.Serialize(
                targets.Select(t => new { t.ChangeType, t.Stage, t.TargetBusinessDays }), CamelCase);
            var id = await _slaRepo.UpsertConfigAsync(json, input);
            return new SaveSlaConfigResult { Saved = true, ConfigId = id, Warnings = warnings };
        }

        public async Task<Guid> AddHolidayAsync(AddSlaHolidayInput input)
        {
            await RequireRoleAsync(input.ActorUserId, "change the holiday calendar", "Admin");
            if (!DateOnly.TryParseExact(input.HolidayDate, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out _))
            {
                throw new ValidationException("Enter the holiday as a valid date (yyyy-MM-dd).");
            }
            if (string.IsNullOrWhiteSpace(input.Reason))
            {
                throw new ValidationException("A reason is required to change the holiday calendar.");
            }
            return await _slaRepo.AddHolidayAsync(input);
        }

        public async Task RemoveHolidayAsync(Guid holidayId, RemoveSlaHolidayInput input)
        {
            await RequireRoleAsync(input.ActorUserId, "change the holiday calendar", "Admin");
            if (string.IsNullOrWhiteSpace(input.Reason))
            {
                throw new ValidationException("A reason is required to change the holiday calendar.");
            }
            await _slaRepo.RemoveHolidayAsync(holidayId, input);
        }

        public async Task<PagedResult<SlaViewRow>> GetViewAsync(SlaViewQuery query)
        {
            await RequireRoleAsync(query.ActorUserId, "view SLA reporting", "Analyst", "Admin");
            return await _slaRepo.GetViewAsync(Normalize(query));
        }

        public async Task<IReadOnlyList<SlaStateCount>> GetSummaryAsync(SlaViewQuery query)
        {
            await RequireRoleAsync(query.ActorUserId, "view SLA reporting", "Analyst", "Admin");
            return await _slaRepo.GetSummaryAsync(Normalize(query));
        }

        /// <summary>Blank filters mean "no filter", and paging is kept to a sane range - the database
        /// clamps the same way, this just keeps the echoed page and page size honest.</summary>
        private static SlaViewQuery Normalize(SlaViewQuery query) => new()
        {
            ActorUserId = query.ActorUserId,
            Stage = NullIfBlank(query.Stage),
            State = NullIfBlank(query.State),
            ChangeType = NullIfBlank(query.ChangeType),
            Search = NullIfBlank(query.Search),
            SortBy = NullIfBlank(query.SortBy),
            SortDir = NullIfBlank(query.SortDir),
            Page = Math.Max(query.Page, 1),
            PageSize = Math.Clamp(query.PageSize, 1, 200),
        };

        public async Task<IReadOnlyList<SlaPerformanceRow>> GetPerformanceAsync(Guid actorUserId, string? changeType)
        {
            await RequireRoleAsync(actorUserId, "view SLA reporting", "Analyst", "Admin");
            return await _slaRepo.GetPerformanceAsync(NullIfBlank(changeType));
        }

        public async Task<IReadOnlyList<RequestSlaRow>> GetRequestSlaAsync(Guid actorUserId, Guid changeRequestId)
        {
            await RequireRoleAsync(actorUserId, "view SLA reporting", "Analyst", "Admin");
            return await _slaRepo.GetRequestSlaAsync(changeRequestId);
        }

        /// <summary>
        /// Every request type needs an overall (start-to-decision) target; per-stage targets are optional.
        /// Whatever is given must be a whole number of business days greater than zero, and nothing is
        /// written if any entry is wrong, missing or repeated (US-19.1 AC3). The message names exactly which
        /// entry is wrong.
        /// </summary>
        private static List<SlaTarget> ValidateTargets(IReadOnlyCollection<SlaTarget>? targets)
        {
            if (targets is null || targets.Count == 0)
            {
                throw new ValidationException("An overall (start to decision) target in business days is required for every request type.");
            }

            var seen = new HashSet<string>();
            foreach (var t in targets)
            {
                var label = $"{t.ChangeType} / {t.Stage}";
                if (!ChangeTypes.Contains(t.ChangeType) || !SlaStages.All.Contains(t.Stage))
                {
                    throw new ValidationException($"Unknown change type or stage: {label}.");
                }
                if (t.TargetBusinessDays < 1)
                {
                    throw new ValidationException($"The {label} target must be a whole number of business days greater than zero.");
                }
                if (!seen.Add(label))
                {
                    throw new ValidationException($"The {label} target was entered more than once.");
                }
            }

            foreach (var type in ChangeTypes)
            {
                if (!seen.Contains($"{type} / {SlaStages.EndToEnd}"))
                {
                    throw new ValidationException($"An overall (start to decision) target is required for {type}.");
                }
            }
            return targets.ToList();
        }

        /// <summary>US-19.1 AC4: stage targets that add up to more than the overall target can never all
        /// be met - warn before accepting (the caller must confirm), but it is not an error. Only the stage
        /// targets actually set count; stages left without a target are ignored.</summary>
        private static List<string> FindInconsistencies(IEnumerable<SlaTarget> targets)
        {
            var warnings = new List<string>();
            foreach (var group in targets.GroupBy(t => t.ChangeType).OrderBy(g => g.Key))
            {
                var endToEnd = group.Single(t => t.Stage == SlaStages.EndToEnd).TargetBusinessDays;
                var stageSum = group.Where(t => t.Stage != SlaStages.EndToEnd).Sum(t => t.TargetBusinessDays);
                if (stageSum > endToEnd)
                {
                    warnings.Add(
                        $"{group.Key}: the stage targets add up to {stageSum} business days, which is more than the {endToEnd}-day overall target.");
                }
            }
            return warnings;
        }

        /// <summary>A user can hold more than one role (Epic 11), so this is a membership check: the actor
        /// must hold at least one of the allowed roles.</summary>
        private async Task RequireRoleAsync(Guid actorUserId, string action, params string[] allowedRoles)
        {
            foreach (var role in allowedRoles)
            {
                if (await _userRepo.HasRoleAsync(actorUserId, role))
                {
                    return;
                }
            }
            var who = allowedRoles.Length == 1 && allowedRoles[0] == "Admin" ? "an Admin" : "an FCRM Analyst or Admin";
            throw new ValidationException($"Only {who} may {action}.");
        }

        private static string? NullIfBlank(string? value) => string.IsNullOrWhiteSpace(value) ? null : value;
    }
}
