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
    /// disabled (the secure-by-default posture - see stghdev01) instead sets BLOB_STORAGE_SERVICE_URI
    /// (just the blob endpoint, e.g. https://stghdev01.blob.core.windows.net - named to match the
    /// Container Apps env var DevOps already provisioned) with no key anywhere, authenticated via
    /// DefaultAzureCredential - same shape as DapperConnectionFactory's
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
            var accountUrl = _configuration["BLOB_STORAGE_SERVICE_URI"];

            BlobServiceClient blobServiceClient;
            if (!string.IsNullOrWhiteSpace(connectionString))
            {
                blobServiceClient = new BlobServiceClient(connectionString);
            }
            else if (!string.IsNullOrWhiteSpace(accountUrl))
            {
                var credentialOptions = BuildCredentialOptions(_configuration);
                blobServiceClient = new BlobServiceClient(new Uri(accountUrl), new DefaultAzureCredential(credentialOptions));
            }
            else
            {
                throw new InvalidOperationException(
                    "Neither BLOB_STORAGE_CONNECTION_STRING nor BLOB_STORAGE_SERVICE_URI is configured - " +
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

        // Extracted so the exclusion rule itself is directly testable (asserting on the returned
        // options) without needing to mock Azure.Identity/Azure.Storage internals or reach for
        // InternalsVisibleTo - see BlobStorageClientTests.cs.
        public static DefaultAzureCredentialOptions BuildCredentialOptions(IConfiguration configuration)
        {
            // ManagedIdentityCredential probes IMDS and, when it's genuinely unreachable (any dev
            // machine, not just this one), throws a hard AuthenticationFailedException rather than
            // the CredentialUnavailableException DefaultAzureCredential's chain expects to fall
            // through on - so it never reaches AzureCliCredential locally.
            //
            // This can't key off IHostEnvironment/ASPNETCORE_ENVIRONMENT: the only environment
            // deployed today (Azure Container Apps dev) also sets ASPNETCORE_ENVIRONMENT to
            // Development, identical to a developer's laptop, and that deployed container is
            // exactly where Managed Identity is the real, only working credential (no interactive
            // az login inside a container, Shared Key access disabled on the storage account).
            // CONTAINER_APP_NAME is what actually distinguishes them - Azure Container Apps
            // injects it automatically into every revision, and no local machine ever has it set.
            var runningInContainerApp = !string.IsNullOrWhiteSpace(configuration["CONTAINER_APP_NAME"]);
            return new DefaultAzureCredentialOptions
            {
                ExcludeManagedIdentityCredential = !runningInContainerApp,
            };
        }
    }
}
