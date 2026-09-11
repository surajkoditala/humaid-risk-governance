namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.ChangeRequests
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.ChangeRequests;

    public interface IChangeRequestRepo
    {
        Task<ChangeRequest> CreateAsync(SubmitChangeRequestInput input);
        Task<ChangeRequest?> GetByIdAsync(Guid changeRequestId);
        Task<IReadOnlyList<ChangeRequestSummary>> GetForUserAsync(Guid userId);

        /// <summary>The analyst inbox - every change request, not scoped to one submitter.</summary>
        Task<IReadOnlyList<ChangeRequestSummary>> GetAllAsync();
        Task UpdateStatusAsync(Guid changeRequestId, string newStatus, Guid? actorUserId);
        Task<(Guid Id, int VersionNumber)> AttachDocumentAsync(AttachDocumentInput input);
        Task<IReadOnlyList<ChangeRequestAttachment>> GetAttachmentsAsync(Guid changeRequestId);
        Task<Guid> RequestClarificationAsync(Guid changeRequestId, Guid requestedByUserId, string question);
    }
}
