namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Ai
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Ai;

    /// <summary>
    /// US-5.1/US-5.2: real Claude call drafting (or regenerating, with feedback) one category's
    /// narrative. Never fabricates a citation - anything not traceable to
    /// <see cref="NarrativeDraftInput"/>'s supplied facts is returned in
    /// <see cref="NarrativeDraftResult.UnsupportedClaims"/> instead of being stated as fact.
    /// </summary>
    public interface INarrativeDraftingAiClient
    {
        Task<NarrativeDraftResult> DraftAsync(NarrativeDraftInput input, CancellationToken cancellationToken = default);
    }
}
