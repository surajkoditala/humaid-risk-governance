namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Assessment
{
    public interface IAssessmentRepo
    {
        Task<Guid> GetOrCreateAsync(Guid changeRequestId);
        Task FinalizeAsync(Guid assessmentId, Guid actorUserId);
        Task<Models.Assessment.Assessment?> GetByChangeRequestAsync(Guid changeRequestId);
        Task<Models.Assessment.Assessment?> GetByIdAsync(Guid assessmentId);
    }
}
