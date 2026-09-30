namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.ChangeRequests
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.ChangeRequests;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core;

    public interface IChangeRequestRepo
    {
        Task<ChangeRequest> CreateAsync(SubmitChangeRequestInput input);
        Task<ChangeRequest?> GetByIdAsync(Guid changeRequestId);
        Task<PagedResult<ChangeRequestSummary>> GetForUserAsync(Guid userId, GridQuery query);

        /// <summary>The analyst inbox - every change request, not scoped to one submitter.</summary>
        Task<PagedResult<ChangeRequestSummary>> GetAllAsync(GridQuery query);
        Task UpdateStatusAsync(Guid changeRequestId, string newStatus, Guid? actorUserId);
        Task<(Guid Id, int VersionNumber)> AttachDocumentAsync(AttachDocumentInput input);
        Task<IReadOnlyList<ChangeRequestAttachment>> GetAttachmentsAsync(Guid changeRequestId);
        Task<string?> GetAttachmentTextAsync(Guid changeRequestId, Guid attachmentId);
        Task<Guid> RequestClarificationAsync(Guid changeRequestId, Guid requestedByUserId, string question);
    }
}
