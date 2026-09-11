namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.DocumentExtraction
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.DocumentExtraction;

    public interface IDocumentExtractionService
    {
        /// <summary>US-4.1: runs <c>IDocumentExtractionAiClient</c> against one attachment's text and
        /// persists each resulting field.</summary>
        Task<IReadOnlyList<ExtractedField>> ExtractAsync(Guid changeRequestId, Guid attachmentId, string changeType, string documentText);

        /// <summary>US-4.2: reason is required only when <paramref name="isMaterialChange"/> is true.</summary>
        Task<Guid> CorrectAsync(CorrectExtractedFieldInput input, bool isMaterialChange);
        Task<IReadOnlyList<ExtractedField>> GetFieldsAsync(Guid changeRequestId);
    }
}
