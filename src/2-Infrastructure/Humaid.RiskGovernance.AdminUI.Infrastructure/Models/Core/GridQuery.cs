namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core
{
    /// <summary>Shared server-side paging/sorting/filtering contract for every list grid
    /// (Assessments inbox, My Requests, Committee Queue) - grid standard raised on the 2026-09-29
    /// sync-up call. SortBy is per-grid (each repo maps it to a fixed, allow-listed column - see
    /// the func_get*.sql functions), so no enum is shared here.</summary>
    public class GridQuery
    {
        public int Page { get; set; } = 1;
        public int PageSize { get; set; } = 10;
        public string? SortBy { get; set; }

        /// <summary>"asc" | "desc".</summary>
        public string? SortDir { get; set; }
        public string? Status { get; set; }
        public string? ChangeType { get; set; }

        /// <summary>Free-text match against title and request number.</summary>
        public string? Search { get; set; }
    }

    public class PagedResult<T>
    {
        public IReadOnlyList<T> Items { get; set; } = Array.Empty<T>();
        public int TotalCount { get; set; }
        public int Page { get; set; }
        public int PageSize { get; set; }
    }
}
