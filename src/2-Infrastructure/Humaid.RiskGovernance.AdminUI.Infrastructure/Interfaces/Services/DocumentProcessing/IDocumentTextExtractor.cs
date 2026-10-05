namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.DocumentProcessing
{
    /// <summary>
    /// Deterministic, non-AI text extraction from an uploaded PDF/DOCX/XLSX - fills the same role
    /// the pasted-text MVP textarea used to (change_request_attachment.extracted_text), now backed
    /// by real parsing instead of a human retyping the document's content. This is exactly the
    /// engineering-judgment "when NOT to use an LLM" case documented in ai/README.md for Epic 3 -
    /// getting text out of a known file format is a solved, deterministic problem.
    /// DocumentExtractionAiClient (the LLM step) runs on this output, unchanged - it only ever
    /// took plain text as input.
    /// </summary>
    public interface IDocumentTextExtractor
    {
        /// <summary>
        /// Returns the extracted plain text, or null for an unsupported/unrecognized content type
        /// - callers should fall back gracefully (needsReview-style), never throw for content the
        /// user legitimately uploaded.
        /// </summary>
        Task<string?> ExtractTextAsync(string contentType, Stream content, CancellationToken cancellationToken = default);
    }
}
