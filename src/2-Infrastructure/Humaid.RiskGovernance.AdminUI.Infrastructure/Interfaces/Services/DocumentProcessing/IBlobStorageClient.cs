namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.DocumentProcessing
{
    /// <summary>
    /// Thin wrapper over Azure.Storage.Blobs (Azurite locally, a real Storage Account in Azure -
    /// see ops/README.md). Fills in what schema/004_change_requests.sql's storage_path column was
    /// deliberately left as "an opaque pointer... this schema doesn't care" for.
    /// </summary>
    public interface IBlobStorageClient
    {
        /// <summary>Uploads the stream and returns its blob URL, stored verbatim as storage_path.</summary>
        Task<string> UploadAsync(string fileName, string contentType, Stream content, CancellationToken cancellationToken = default);
    }
}
