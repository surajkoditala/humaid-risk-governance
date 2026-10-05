namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Ai
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Ai;

    /// <summary>
    /// US-4.1: real Claude call producing structured fields from a document's text. MVP: operates
    /// on already-extracted plain text (see ChangeRequestAttachment.ExtractedText) - no PDF/DOCX
    /// parser in this pass.
    /// </summary>
    public interface IDocumentExtractionAiClient
    {
        Task<IReadOnlyList<ExtractedFieldProposal>> ExtractAsync(
            string changeType,
            string documentText,
            CancellationToken cancellationToken = default);
    }
}
