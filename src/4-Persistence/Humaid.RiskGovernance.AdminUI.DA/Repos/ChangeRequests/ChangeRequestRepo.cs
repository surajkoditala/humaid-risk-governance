namespace Humaid.RiskGovernance.AdminUI.DA.Repos.ChangeRequests
{
    using Dapper;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.ChangeRequests;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.ChangeRequests;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core;

    /// <summary>Every method here calls one stored function - see
    /// Humaid.RiskGovernance.AdminUI.DB/functions/change_requests/.</summary>
    public class ChangeRequestRepo : IChangeRequestRepo
    {
        private readonly DapperConnectionFactory _connectionFactory;

        public ChangeRequestRepo(DapperConnectionFactory connectionFactory)
        {
            _connectionFactory = connectionFactory;
        }

        public async Task<ChangeRequest> CreateAsync(SubmitChangeRequestInput input)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            var created = await conn.QuerySingleAsync<ChangeRequest>(
                "SELECT * FROM func_createChangeRequest(@ChangeType, @Title, @Description, @TypeSpecificFieldsJson::jsonb, @SubmittedByUserId)",
                new { input.ChangeType, input.Title, input.Description, input.TypeSpecificFieldsJson, input.SubmittedByUserId });

            created.ChangeType = input.ChangeType;
            created.Title = input.Title;
            created.Description = input.Description;
            created.TypeSpecificFieldsJson = input.TypeSpecificFieldsJson;
            created.SubmittedByUserId = input.SubmittedByUserId;
            return created;
        }

        public async Task<ChangeRequest?> GetByIdAsync(Guid changeRequestId)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            return await conn.QuerySingleOrDefaultAsync<ChangeRequest>(
                "SELECT * FROM func_getChangeRequestById(@changeRequestId)", new { changeRequestId });
        }

        public async Task<PagedResult<ChangeRequestSummary>> GetForUserAsync(Guid userId, GridQuery query)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            var rows = (await conn.QueryAsync<ChangeRequestSummaryRow>(
                @"SELECT * FROM func_getChangeRequestsForUser(
                    @userId, @Status, @ChangeType, @Search, @SortBy, @SortDir, @Page, @PageSize)",
                new { userId, query.Status, query.ChangeType, query.Search, query.SortBy, query.SortDir, query.Page, query.PageSize })).AsList();
            return ToPagedResult(rows, query);
        }

        public async Task<PagedResult<ChangeRequestSummary>> GetAllAsync(GridQuery query)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            var rows = (await conn.QueryAsync<ChangeRequestSummaryRow>(
                "SELECT * FROM func_getAllChangeRequests(@Status, @ChangeType, @Search, @SortBy, @SortDir, @Page, @PageSize)",
                new { query.Status, query.ChangeType, query.Search, query.SortBy, query.SortDir, query.Page, query.PageSize })).AsList();
            return ToPagedResult(rows, query);
        }

        private static PagedResult<ChangeRequestSummary> ToPagedResult(IReadOnlyList<ChangeRequestSummaryRow> rows, GridQuery query) =>
            new()
            {
                Items = rows,
                TotalCount = rows.Count > 0 ? (int)rows[0].TotalCount : 0,
                Page = query.Page,
                PageSize = query.PageSize,
            };

        /// <summary>Widens ChangeRequestSummary with the window-function total_count column the
        /// paged func_get* functions return alongside every row.</summary>
        private class ChangeRequestSummaryRow : ChangeRequestSummary
        {
            public long TotalCount { get; set; }
        }

        public async Task UpdateStatusAsync(Guid changeRequestId, string newStatus, Guid? actorUserId)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            await conn.ExecuteAsync(
                "SELECT func_updateChangeRequestStatus(@changeRequestId, @newStatus, @actorUserId)",
                new { changeRequestId, newStatus, actorUserId });
        }

        public async Task<(Guid Id, int VersionNumber)> AttachDocumentAsync(AttachDocumentInput input)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            var row = await conn.QuerySingleAsync<AttachResultRow>(
                @"SELECT * FROM func_attachDocument(
                    @ChangeRequestId, @FileName, @ContentType, @StoragePath, @ExtractedText,
                    @UploadedByUserId, @SupersedesAttachmentId)",
                new
                {
                    input.ChangeRequestId,
                    input.FileName,
                    input.ContentType,
                    input.StoragePath,
                    input.ExtractedText,
                    input.UploadedByUserId,
                    input.SupersedesAttachmentId,
                });
            return (row.Id, row.VersionNumber);
        }

        public async Task<IReadOnlyList<ChangeRequestAttachment>> GetAttachmentsAsync(Guid changeRequestId)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            var rows = await conn.QueryAsync<ChangeRequestAttachment>(
                "SELECT * FROM func_getAttachments(@changeRequestId)", new { changeRequestId });
            return rows.AsList();
        }

        public async Task<string?> GetAttachmentTextAsync(Guid changeRequestId, Guid attachmentId)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            return await conn.QuerySingleOrDefaultAsync<string?>(
                "SELECT func_getAttachmentText(@changeRequestId, @attachmentId)", new { changeRequestId, attachmentId });
        }

        public async Task<Guid> RequestClarificationAsync(Guid changeRequestId, Guid requestedByUserId, string question)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            return await conn.QuerySingleAsync<Guid>(
                "SELECT func_requestClarification(@changeRequestId, @requestedByUserId, @question)",
                new { changeRequestId, requestedByUserId, question });
        }

        private class AttachResultRow
        {
            public Guid Id { get; set; }
            public int VersionNumber { get; set; }
        }
    }
}
