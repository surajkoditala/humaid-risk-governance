namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.PolicyResearch
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.PolicyResearch;

    public interface IPolicyResearchRepo
    {
        Task<IReadOnlyList<PolicyChunkSearchResult>> SearchChunksAsync(string queryText, Guid? riskCategoryId, int topK);
        Task<Guid> RecordRelianceAsync(RecordPolicyRelianceInput input);
        Task<IReadOnlyList<PolicyReliance>> GetRelianceAsync(Guid assessmentId);
    }
}
