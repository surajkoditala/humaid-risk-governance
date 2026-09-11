namespace Humaid.RiskGovernance.AdminUI.Services.DocumentExtraction
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Ai;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.DocumentExtraction;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.DocumentExtraction;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.DocumentExtraction;

    public class DocumentExtractionService : IDocumentExtractionService
    {
        private readonly IExtractedFieldRepo _extractedFieldRepo;
        private readonly IDocumentExtractionAiClient _aiClient;

        public DocumentExtractionService(IExtractedFieldRepo extractedFieldRepo, IDocumentExtractionAiClient aiClient)
        {
            _extractedFieldRepo = extractedFieldRepo;
            _aiClient = aiClient;
        }

        public async Task<IReadOnlyList<ExtractedField>> ExtractAsync(Guid changeRequestId, Guid attachmentId, string changeType, string documentText)
        {
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
