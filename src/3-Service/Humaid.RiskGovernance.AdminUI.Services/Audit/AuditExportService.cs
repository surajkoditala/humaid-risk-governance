namespace Humaid.RiskGovernance.AdminUI.Services.Audit
{
    using System.Text.Json;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.ChangeRequests;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Audit;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Audit;
    using QuestPDF.Fluent;
    using QuestPDF.Helpers;
    using QuestPDF.Infrastructure;

    /// <summary>US-9.3. Deterministic layout, not an AI call - see CLAUDE.md's "engineering
    /// judgement: when NOT to use an LLM" criterion. Renders exactly what GetTrailAsync already
    /// returns; adds no data of its own.</summary>
    public class AuditExportService : IAuditExportService
    {
        private readonly IAuditService _auditService;
        private readonly IChangeRequestRepo _changeRequestRepo;

        public AuditExportService(IAuditService auditService, IChangeRequestRepo changeRequestRepo)
        {
            _auditService = auditService;
            _changeRequestRepo = changeRequestRepo;
        }

        public async Task<byte[]> ExportPdfAsync(Guid changeRequestId)
        {
            var changeRequest = await _changeRequestRepo.GetByIdAsync(changeRequestId)
                ?? throw new InvalidOperationException($"Change request {changeRequestId} not found.");
            var trail = await _auditService.GetTrailAsync(changeRequestId);

            var document = Document.Create(container =>
            {
                container.Page(page =>
                {
                    page.Size(PageSizes.A4);
                    page.Margin(36);
                    page.DefaultTextStyle(x => x.FontSize(9));

                    page.Header().Column(col =>
                    {
                        col.Item().Text("Audit Trail Export").FontSize(18).Bold();
                        col.Item().Text($"{changeRequest.RequestNumber} — {changeRequest.Title}").FontSize(12);
                        col.Item().Text($"Change type: {changeRequest.ChangeType}   |   Status: {changeRequest.Status}   |   Submitted: {changeRequest.SubmittedAt:yyyy-MM-dd HH:mm} UTC").FontSize(9).FontColor(Colors.Grey.Darken1);
                        col.Item().Text($"Generated: {DateTimeOffset.UtcNow:yyyy-MM-dd HH:mm} UTC").FontSize(8).FontColor(Colors.Grey.Medium);
                        col.Item().PaddingTop(6).LineHorizontal(1).LineColor(Colors.Grey.Lighten1);
                    });

                    page.Content().PaddingTop(10).Table(table =>
                    {
                        table.ColumnsDefinition(columns =>
                        {
                            columns.ConstantColumn(85); // timestamp
                            columns.ConstantColumn(70); // entity/action
                            columns.ConstantColumn(70); // actor
                            columns.RelativeColumn();   // detail (before/after/reason)
                        });

                        void HeaderCell(string text) => table.Cell().Background(Colors.Grey.Lighten3).Padding(4).Text(text).Bold();
                        HeaderCell("When");
                        HeaderCell("Event");
                        HeaderCell("Actor");
                        HeaderCell("Detail");

                        foreach (var e in trail.OrderBy(e => e.CreatedAt))
                        {
                            var actor = e.ActorLabel == "human" ? (e.ActorName ?? "(unknown)") : "system/AI";
                            var detail = BuildDetail(e);

                            table.Cell().BorderBottom(0.5f).BorderColor(Colors.Grey.Lighten2).Padding(4).Text(e.CreatedAt.ToString("yyyy-MM-dd HH:mm:ss"));
                            table.Cell().BorderBottom(0.5f).BorderColor(Colors.Grey.Lighten2).Padding(4).Text($"{e.EntityType}.{e.Action}");
                            table.Cell().BorderBottom(0.5f).BorderColor(Colors.Grey.Lighten2).Padding(4).Text(actor);
                            table.Cell().BorderBottom(0.5f).BorderColor(Colors.Grey.Lighten2).Padding(4).Text(detail);
                        }
                    });

                    page.Footer().AlignCenter().Text(x =>
                    {
                        x.Span("Humaid Risk Governance — Risk Assessment Workbench. Page ");
                        x.CurrentPageNumber();
                        x.Span(" of ");
                        x.TotalPages();
                    });
                });
            });

            return document.GeneratePdf();
        }

        private static string BuildDetail(AuditEvent e)
        {
            var parts = new List<string>();
            if (!string.IsNullOrWhiteSpace(e.Reason)) parts.Add($"Reason: {e.Reason}");
            var after = SummarizeJson(e.AfterValueJson);
            if (after is not null) parts.Add($"After: {after}");
            var before = SummarizeJson(e.BeforeValueJson);
            if (before is not null) parts.Add($"Before: {before}");
            return parts.Count > 0 ? string.Join("  |  ", parts) : "—";
        }

        private static string? SummarizeJson(string? json)
        {
            if (string.IsNullOrWhiteSpace(json)) return null;
            try
            {
                using var doc = JsonDocument.Parse(json);
                var pairs = doc.RootElement.EnumerateObject().Select(p => $"{p.Name}={p.Value}");
                return string.Join(", ", pairs);
            }
            catch (JsonException)
            {
                return json;
            }
        }
    }
}
