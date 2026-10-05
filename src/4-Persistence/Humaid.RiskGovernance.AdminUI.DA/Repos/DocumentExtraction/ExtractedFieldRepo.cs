namespace Humaid.RiskGovernance.AdminUI.DA.Repos.DocumentExtraction
{
    using Dapper;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.DocumentExtraction;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.DocumentExtraction;

    public class ExtractedFieldRepo : IExtractedFieldRepo
    {
        private readonly DapperConnectionFactory _connectionFactory;

        public ExtractedFieldRepo(DapperConnectionFactory connectionFactory)
        {
            _connectionFactory = connectionFactory;
        }

        public async Task<Guid> SaveFieldAsync(Guid changeRequestId, Guid? attachmentId, string fieldKey, string? fieldValue,
            decimal? confidence, bool needsReview, string? sourceExcerpt)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            return await conn.QuerySingleAsync<Guid>(
                @"SELECT func_saveExtractedField(
                    @changeRequestId, @attachmentId, @fieldKey, @fieldValue, @confidence, @needsReview, @sourceExcerpt)",
                new { changeRequestId, attachmentId, fieldKey, fieldValue, confidence, needsReview, sourceExcerpt });
        }

        public async Task<Guid> CorrectFieldAsync(CorrectExtractedFieldInput input)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            return await conn.QuerySingleAsync<Guid>(
                "SELECT func_correctExtractedField(@ChangeRequestId, @FieldKey, @NewValue, @Reason, @ActorUserId)",
                input);
        }

        public async Task<IReadOnlyList<ExtractedField>> GetFieldsAsync(Guid changeRequestId)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            var rows = await conn.QueryAsync<ExtractedField>(
                "SELECT * FROM func_getExtractedFields(@changeRequestId)", new { changeRequestId });
            return rows.AsList();
        }
    }
}
