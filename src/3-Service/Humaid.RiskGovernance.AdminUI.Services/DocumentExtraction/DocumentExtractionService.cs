namespace Humaid.RiskGovernance.AdminUI.Services.DocumentExtraction
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Ai;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.ChangeRequests;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.DocumentExtraction;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.DocumentExtraction;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.DocumentExtraction;

    public class DocumentExtractionService : IDocumentExtractionService
    {
        private readonly IExtractedFieldRepo _extractedFieldRepo;
        private readonly IChangeRequestRepo _changeRequestRepo;
        private readonly IDocumentExtractionAiClient _aiClient;

        public DocumentExtractionService(
            IExtractedFieldRepo extractedFieldRepo, IChangeRequestRepo changeRequestRepo, IDocumentExtractionAiClient aiClient)
        {
            _extractedFieldRepo = extractedFieldRepo;
            _changeRequestRepo = changeRequestRepo;
            _aiClient = aiClient;
        }

        public async Task<IReadOnlyList<ExtractedField>> ExtractAsync(Guid changeRequestId, Guid attachmentId, string changeType)
        {
            // DEF-020: the webapp had been sending attachment.fileName as "documentText" - the
            // attachment's actual extracted text was never in the client's hands to send. Load it
            // here, server-side, by attachmentId instead of trusting whatever the caller supplies.
            //
            // AI review on PR #60: attachmentId alone let a caller pair one change request's id
            // with another request's attachment, extracting and saving that other request's text
            // onto this one. func_getAttachmentText now requires both ids to match, so a mismatch
            // falls into the same "not available" error a caller can't distinguish from a missing
            // attachment.
            var documentText = await _changeRequestRepo.GetAttachmentTextAsync(changeRequestId, attachmentId);
            if (string.IsNullOrWhiteSpace(documentText))
                throw new ValidationException("No extracted text is available for this attachment yet.");

            var proposals = await _aiClient.ExtractAsync(changeType, documentText);
            foreach (var proposal in proposals)
            {
                await _extractedFieldRepo.SaveFieldAsync(
                    changeRequestId, attachmentId, proposal.FieldKey, proposal.FieldValue,
                    proposal.Confidence, proposal.NeedsReview, proposal.SourceExcerpt);
            }
            return await _extractedFieldRepo.GetFieldsAsync(changeRequestId);
        }

        public Task<Guid> CorrectAsync(CorrectExtractedFieldInput input, bool isMaterialChange)
        {
            // US-4.2 AC1: reason required only when the edit materially changes the field's meaning.
            if (isMaterialChange && string.IsNullOrWhiteSpace(input.Reason))
            {
                throw new ValidationException(
                    "A reason is required for this correction - it materially changes the field's meaning.");
            }
            return _extractedFieldRepo.CorrectFieldAsync(input);
        }

        public Task<IReadOnlyList<ExtractedField>> GetFieldsAsync(Guid changeRequestId) => _extractedFieldRepo.GetFieldsAsync(changeRequestId);
    }
}
