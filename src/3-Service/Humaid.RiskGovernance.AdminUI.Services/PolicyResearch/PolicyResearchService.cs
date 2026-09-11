namespace Humaid.RiskGovernance.AdminUI.Services.PolicyResearch
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.PolicyResearch;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.PolicyResearch;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.PolicyResearch;

    public class PolicyResearchService : IPolicyResearchService
    {
        private readonly IPolicyResearchRepo _policyResearchRepo;

        public PolicyResearchService(IPolicyResearchRepo policyResearchRepo)
        {
            _policyResearchRepo = policyResearchRepo;
        }

        public Task<IReadOnlyList<PolicyChunkSearchResult>> SearchAsync(string queryText, Guid? riskCategoryId, int topK = 5) =>
            _policyResearchRepo.SearchChunksAsync(queryText, riskCategoryId, topK);

        public Task<Guid> RecordRelianceAsync(RecordPolicyRelianceInput input) => _policyResearchRepo.RecordRelianceAsync(input);

        public Task<IReadOnlyList<PolicyReliance>> GetRelianceAsync(Guid assessmentId) => _policyResearchRepo.GetRelianceAsync(assessmentId);
    }
}
