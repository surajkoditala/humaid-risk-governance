namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.DocumentExtraction
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.DocumentExtraction;

    public interface IExtractedFieldRepo
    {
        Task<Guid> SaveFieldAsync(Guid changeRequestId, Guid? attachmentId, string fieldKey, string? fieldValue,
            decimal? confidence, bool needsReview, string? sourceExcerpt);
        Task<Guid> CorrectFieldAsync(CorrectExtractedFieldInput input);
        Task<IReadOnlyList<ExtractedField>> GetFieldsAsync(Guid changeRequestId);
    }
}
