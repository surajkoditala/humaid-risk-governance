namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Models.RiskFramework
{
    /// <summary>One of the four FFIEC BSA/AML categories (see seed_ffiec_framework.sql).</summary>
    public class RiskCategory
    {
        public Guid Id { get; set; }
        public string Code { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public string CitationSection { get; set; } = string.Empty;
    }

    /// <summary>
    /// One row of CLAUDE.md's change-type -> category lookup, sent to <c>ICategoryMappingAiClient</c>
    /// as grounding so it proposes from this fixed list rather than inventing categories.
    /// </summary>
    public class ChangeTypeCategoryDefault
    {
        public Guid RiskCategoryId { get; set; }
        public string Code { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public string CitationSection { get; set; } = string.Empty;

        /// <summary>Primary | Secondary.</summary>
        public string Weight { get; set; } = string.Empty;
    }
}
