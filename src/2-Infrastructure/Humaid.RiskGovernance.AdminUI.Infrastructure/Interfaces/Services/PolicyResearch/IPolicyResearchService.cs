namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.PolicyResearch
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.PolicyResearch;

    public interface IPolicyResearchService
    {
        Task<IReadOnlyList<PolicyChunkSearchResult>> SearchAsync(string queryText, Guid? riskCategoryId, int topK = 5);
        Task<Guid> RecordRelianceAsync(RecordPolicyRelianceInput input);
        Task<IReadOnlyList<PolicyReliance>> GetRelianceAsync(Guid assessmentId);
    }
}
