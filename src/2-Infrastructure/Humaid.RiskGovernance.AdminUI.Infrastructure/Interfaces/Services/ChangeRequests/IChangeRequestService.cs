namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.ChangeRequests
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.ChangeRequests;

    public interface IChangeRequestService
    {
        Task<ChangeRequest> SubmitAsync(SubmitChangeRequestInput input);
        Task<ChangeRequest?> GetByIdAsync(Guid changeRequestId);
        Task<IReadOnlyList<ChangeRequestSummary>> GetMyRequestsAsync(Guid userId);
        Task<IReadOnlyList<ChangeRequestSummary>> GetAllAsync();
        Task<(Guid Id, int VersionNumber)> AttachDocumentAsync(AttachDocumentInput input);

        /// <summary>
        /// Phase 3 Step 4 - a real uploaded file, not pasted text. Uploads to blob storage,
        /// extracts its text deterministically, then delegates to <see cref="AttachDocumentAsync"/>
        /// with the result - see ChangeRequestService.
        /// </summary>
        Task<(Guid Id, int VersionNumber)> AttachDocumentFileAsync(
            Guid changeRequestId, string fileName, string contentType, Stream content, Guid uploadedByUserId, Guid? supersedesAttachmentId);
        Task<IReadOnlyList<ChangeRequestAttachment>> GetAttachmentsAsync(Guid changeRequestId);
        Task<Guid> RequestClarificationAsync(Guid changeRequestId, Guid requestedByUserId, string question);
    }
}
