namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Scoring
{
    /// <summary>Epic 7 - one category's inherent/residual score within an assessment.</summary>
    public class RiskScore
    {
        public Guid Id { get; set; }
        public Guid RiskCategoryId { get; set; }
        public string CategoryName { get; set; } = string.Empty;
        public decimal InherentRating { get; set; }
        public decimal ControlEffectiveness { get; set; }
        public decimal MitigationFactorApplied { get; set; }
        public decimal ResidualRating { get; set; }
        public bool IsOverride { get; set; }
        public string? OverrideReason { get; set; }

        /// <summary>System | Analyst.</summary>
        public string ScoredBy { get; set; } = string.Empty;
    }

    public class Control
    {
        public Guid Id { get; set; }
        public string Name { get; set; } = string.Empty;
        public string? Description { get; set; }
    }

    public class CalculateRiskScoreInput
    {
        public Guid AssessmentId { get; set; }
        public Guid RiskCategoryId { get; set; }

        /// <summary>1-5 scale (Low..Very High) - see schema/010_scoring.sql for why this floor matters.</summary>
        public decimal InherentRating { get; set; }
        public List<Guid> ControlIdsCredited { get; set; } = [];

        /// <summary>0-1: how effective the credited controls are, before the configured mitigation cap is applied.</summary>
        public decimal ControlEffectiveness { get; set; }
    }

    public class OverrideRiskScoreInput
    {
        public Guid AssessmentId { get; set; }
        public Guid RiskCategoryId { get; set; }
        public decimal NewResidualRating { get; set; }
        public string Reason { get; set; } = string.Empty;
        public Guid ActorUserId { get; set; }
    }

    public class UpsertScoringConfigInput
    {
        public Guid RiskCategoryId { get; set; }

        /// <summary>Must be in [0, 1.0) - a value of 1.0+ would let residual risk reach zero (US-10.1 AC2).</summary>
        public decimal MaxMitigationFactor { get; set; }
        public string Reason { get; set; } = string.Empty;
        public Guid ActorUserId { get; set; }
    }
}
