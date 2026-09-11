namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Narrative
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Narrative;

    public interface INarrativeService
    {
        /// <summary>US-5.1 (first draft) and US-5.2 (regenerate with feedback, when
        /// <paramref name="regenerationFeedback"/> is supplied) - both call
        /// <c>INarrativeDraftingAiClient</c> and persist an 'AiDrafted' section.</summary>
        Task<NarrativeSection> DraftAsync(Guid assessmentId, Guid riskCategoryId, string? regenerationFeedback = null);

        /// <summary>US-6.3: accept an AI draft as-is - no reason required, it isn't an edit.</summary>
        Task<Guid> ReviewAsync(Guid assessmentId, Guid riskCategoryId, Guid actorUserId);

        /// <summary>US-6.1: edit the narrative text - reason mandatory.</summary>
        Task<Guid> EditAsync(EditNarrativeSectionInput input);
        Task<IReadOnlyList<NarrativeSection>> GetSectionsAsync(Guid assessmentId);
    }
}
