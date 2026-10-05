namespace Humaid.RiskGovernance.AdminUI.Services.DocumentProcessing
{
    using System.Text;
    using DocumentFormat.OpenXml.Packaging;
    using DocumentFormat.OpenXml.Spreadsheet;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.DocumentProcessing;
    using Microsoft.Extensions.Logging;
    using UglyToad.PdfPig;

    public class DocumentTextExtractor : IDocumentTextExtractor
    {
        private const string PdfContentType = "application/pdf";
        private const string DocxContentType = "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
        private const string XlsxContentType = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";

        private readonly ILogger<DocumentTextExtractor> _logger;

        public DocumentTextExtractor(ILogger<DocumentTextExtractor> logger)
        {
            _logger = logger;
        }

        public Task<string?> ExtractTextAsync(string contentType, Stream content, CancellationToken cancellationToken = default)
        {
            try
            {
                var text = contentType switch
                {
                    PdfContentType => ExtractPdf(content),
                    DocxContentType => ExtractDocx(content),
                    XlsxContentType => ExtractXlsx(content),
                    _ => null,
                };
                return Task.FromResult(text);
            }
            catch (Exception ex)
            {
                // Deterministic parsing failing (a corrupt or password-protected file, say) must
                // not fail the whole upload - the attachment still gets stored, just without
                // extracted_text, and DocumentExtractionAiClient simply has nothing to run against
                // for it (US-4.1's own "extract only what's actually there" rule, one level up).
                _logger.LogWarning(ex, "Document text extraction failed for content type {ContentType}.", contentType);
                return Task.FromResult<string?>(null);
            }
        }

        private static string ExtractPdf(Stream content)
        {
            using var document = PdfDocument.Open(content);
            var sb = new StringBuilder();
            foreach (var page in document.GetPages())
            {
                sb.AppendLine(page.Text);
            }
            return sb.ToString().Trim();
        }

        private static string ExtractDocx(Stream content)
        {
            using var document = WordprocessingDocument.Open(content, false);
            return document.MainDocumentPart?.Document?.Body?.InnerText.Trim() ?? string.Empty;
        }

        private static string ExtractXlsx(Stream content)
        {
            using var document = SpreadsheetDocument.Open(content, false);
            var workbookPart = document.WorkbookPart ?? throw new InvalidOperationException("XLSX has no workbook part.");
            var sharedStrings = workbookPart.SharedStringTablePart?.SharedStringTable
                .Elements<SharedStringItem>().Select(s => s.InnerText).ToList() ?? [];

            var sb = new StringBuilder();
            foreach (var sheetPart in workbookPart.WorksheetParts)
            {
                foreach (var cell in sheetPart.Worksheet.Descendants<Cell>())
                {
                    var value = cell.CellValue?.InnerText;
                    if (string.IsNullOrEmpty(value)) continue;

                    if (cell.DataType?.Value == CellValues.SharedString && int.TryParse(value, out var index) && index < sharedStrings.Count)
                    {
                        sb.Append(sharedStrings[index]).Append(' ');
                    }
                    else
                    {
                        sb.Append(value).Append(' ');
                    }
                }
                sb.AppendLine();
            }
            return sb.ToString().Trim();
        }
    }
}
