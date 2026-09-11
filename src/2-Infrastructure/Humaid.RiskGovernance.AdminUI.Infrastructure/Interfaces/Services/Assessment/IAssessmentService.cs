namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Assessment
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Assessment;

    public interface IAssessmentService
    {
        Task<Guid> OpenWorkspaceAsync(Guid changeRequestId);
        Task<Assessment?> GetByChangeRequestAsync(Guid changeRequestId);

        /// <summary>US-6.3 AC1: what's outstanding, without attempting to finalize.</summary>
        Task<AssessmentReadiness> CheckReadinessAsync(Guid assessmentId);

        /// <summary>US-6.3: throws <see cref="InvalidOperationException"/> (mapped to 400 by the
        /// controller) listing what's outstanding if <see cref="CheckReadinessAsync"/> would fail.</summary>
        Task FinalizeAsync(Guid assessmentId, Guid actorUserId);
    }
}
