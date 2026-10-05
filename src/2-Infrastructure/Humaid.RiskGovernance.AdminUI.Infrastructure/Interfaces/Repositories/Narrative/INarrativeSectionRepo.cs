namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Narrative
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Narrative;

    public interface INarrativeSectionRepo
    {
        Task<Guid> SaveDraftAsync(Guid assessmentId, Guid riskCategoryId, string narrativeText, string unsupportedClaimFlagsJson);
        Task<Guid> ReviewAsync(Guid assessmentId, Guid riskCategoryId, Guid actorUserId);
        Task<Guid> EditAsync(EditNarrativeSectionInput input);
        Task<IReadOnlyList<NarrativeSection>> GetSectionsAsync(Guid assessmentId);
    }
}
