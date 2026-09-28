namespace Humaid.RiskGovernance.AdminUI.Services.DocumentExtraction
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Ai;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.ChangeRequests;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.DocumentExtraction;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.DocumentExtraction;
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
            var documentText = await _changeRequestRepo.GetAttachmentTextAsync(attachmentId);
            if (string.IsNullOrWhiteSpace(documentText))
                throw new InvalidOperationException("No extracted text is available for this attachment yet.");

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
                throw new InvalidOperationException(
                    "A reason is required for this correction - it materially changes the field's meaning.");
            }
            return _extractedFieldRepo.CorrectFieldAsync(input);
        }

        public Task<IReadOnlyList<ExtractedField>> GetFieldsAsync(Guid changeRequestId) => _extractedFieldRepo.GetFieldsAsync(changeRequestId);
    }
}
