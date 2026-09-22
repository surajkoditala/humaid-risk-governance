namespace Humaid.RiskGovernance.AdminUI.Services.DocumentProcessing
{
    using Azure.Identity;
    using Azure.Storage.Blobs;
    using Azure.Storage.Blobs.Models;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.DocumentProcessing;
    using Microsoft.Extensions.Configuration;

    /// <summary>
    /// Local dev talks to Azurite (ops/docker-compose.yml) with its well-known emulator connection
    /// string via BLOB_STORAGE_CONNECTION_STRING; a real Storage Account with Shared Key access
    /// disabled (the secure-by-default posture - see stghdev01) instead sets BLOB_STORAGE_ACCOUNT_URL
    /// (just the blob endpoint, e.g. https://stghdev01.blob.core.windows.net) with no key anywhere,
    /// authenticated via DefaultAzureCredential - same shape as DapperConnectionFactory's
    /// AZURE_POSTGRESQL_CONNECTIONSTRING/AZURE_POSTGRESQL_ENDPOINT split for Postgres. Same
    /// "flag explicitly, don't silently guess" rule as every other external client in this repo
    /// (ClaudeApiClient, MockSystemsClient).
    /// </summary>
    public class BlobStorageClient : IBlobStorageClient
    {
        private const string ContainerName = "change-request-attachments";

        private readonly IConfiguration _configuration;

        public BlobStorageClient(IConfiguration configuration)
        {
            // Config is validated at call time (UploadAsync), not here - ChangeRequestService
            // takes this by constructor injection, so every ChangeRequest request (not just file
            // uploads) would fail at DI-resolution time otherwise. Same "fail loudly, but only
            // when actually asked to do the thing" rule as ClaudeApiClient/MockSystemsClient.
            _configuration = configuration;
        }

        public async Task<string> UploadAsync(string fileName, string contentType, Stream content, CancellationToken cancellationToken = default)
        {
            var connectionString = _configuration["BLOB_STORAGE_CONNECTION_STRING"];
            var accountUrl = _configuration["BLOB_STORAGE_ACCOUNT_URL"];

            BlobServiceClient blobServiceClient;
            if (!string.IsNullOrWhiteSpace(connectionString))
            {
                blobServiceClient = new BlobServiceClient(connectionString);
            }
            else if (!string.IsNullOrWhiteSpace(accountUrl))
            {
                blobServiceClient = new BlobServiceClient(new Uri(accountUrl), new DefaultAzureCredential());
            }
            else
            {
                throw new InvalidOperationException(
                    "Neither BLOB_STORAGE_CONNECTION_STRING nor BLOB_STORAGE_ACCOUNT_URL is configured - " +
                    "set the former to Azurite's emulator connection string for local dev (see " +
                    "ops/docker-compose.yml), or the latter to a real Storage Account's blob endpoint " +
                    "when Shared Key access is disabled there.");
            }

            var containerClient = blobServiceClient.GetBlobContainerClient(ContainerName);
            await containerClient.CreateIfNotExistsAsync(cancellationToken: cancellationToken);

            // A GUID prefix, not the raw file name, so two analysts uploading "policy.pdf" the same
            // day never collide - the human-readable name is still preserved in change_request_attachment.file_name.
            var blobName = $"{Guid.NewGuid()}-{fileName}";
            var blobClient = containerClient.GetBlobClient(blobName);

            await blobClient.UploadAsync(
                content,
                new BlobUploadOptions { HttpHeaders = new BlobHttpHeaders { ContentType = contentType } },
                cancellationToken);

            return blobClient.Uri.ToString();
        }
    }
}
