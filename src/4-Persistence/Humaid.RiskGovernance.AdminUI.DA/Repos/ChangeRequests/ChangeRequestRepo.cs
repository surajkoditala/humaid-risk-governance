namespace Humaid.RiskGovernance.AdminUI.DA.Repos.ChangeRequests
{
    using Dapper;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.ChangeRequests;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.ChangeRequests;

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

        public async Task<IReadOnlyList<ChangeRequestSummary>> GetForUserAsync(Guid userId)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            var rows = await conn.QueryAsync<ChangeRequestSummary>(
                "SELECT * FROM func_getChangeRequestsForUser(@userId)", new { userId });
            return rows.AsList();
        }

        public async Task<IReadOnlyList<ChangeRequestSummary>> GetAllAsync()
        {
            await using var conn = await _connectionFactory.OpenAsync();
            var rows = await conn.QueryAsync<ChangeRequestSummary>("SELECT * FROM func_getAllChangeRequests()");
            return rows.AsList();
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
