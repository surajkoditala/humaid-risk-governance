using System.Security.Claims;
using Humaid.RiskGovernance.AdminUI.AI;
using Humaid.RiskGovernance.AdminUI.DA;
using Humaid.RiskGovernance.AdminUI.DA.Repos.Assessment;
using Humaid.RiskGovernance.AdminUI.DA.Repos.Audit;
using Humaid.RiskGovernance.AdminUI.DA.Repos.CategoryMapping;
using Humaid.RiskGovernance.AdminUI.DA.Repos.ChangeRequests;
using Humaid.RiskGovernance.AdminUI.DA.Repos.Committee;
using Humaid.RiskGovernance.AdminUI.DA.Repos.Configuration;
using Humaid.RiskGovernance.AdminUI.DA.Repos.DataIngestion;
using Humaid.RiskGovernance.AdminUI.DA.Repos.DocumentExtraction;
using Humaid.RiskGovernance.AdminUI.DA.Repos.Narrative;
using Humaid.RiskGovernance.AdminUI.DA.Repos.PolicyResearch;
using Humaid.RiskGovernance.AdminUI.DA.Repos.Scoring;
using Humaid.RiskGovernance.AdminUI.DA.Repos.Users;
using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Ai;
using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Assessment;
using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Audit;
using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.CategoryMapping;
using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.ChangeRequests;
using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Committee;
using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Configuration;
using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.DataIngestion;
using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.DocumentExtraction;
using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Narrative;
using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.PolicyResearch;
using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Scoring;
using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Users;
using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Assessment;
using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Audit;
using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.CategoryMapping;
using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.ChangeRequests;
using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Committee;
using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Configuration;
using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.DataIngestion;
using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.DocumentExtraction;
using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.DocumentProcessing;
using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Narrative;
using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.PolicyResearch;
using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Scoring;
using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Users;
using Humaid.RiskGovernance.AdminUI.Services.Assessment;
using Humaid.RiskGovernance.AdminUI.Services.Audit;
using Humaid.RiskGovernance.AdminUI.Services.CategoryMapping;
using Humaid.RiskGovernance.AdminUI.Services.ChangeRequests;
using Humaid.RiskGovernance.AdminUI.Services.Committee;
using Humaid.RiskGovernance.AdminUI.Services.Configuration;
using Humaid.RiskGovernance.AdminUI.Services.DataIngestion;
using Humaid.RiskGovernance.AdminUI.Services.DocumentExtraction;
using Humaid.RiskGovernance.AdminUI.Services.DocumentProcessing;
using Humaid.RiskGovernance.AdminUI.Services.Narrative;
using Humaid.RiskGovernance.AdminUI.Services.PolicyResearch;
using Humaid.RiskGovernance.AdminUI.Services.Scoring;
using Humaid.RiskGovernance.AdminUI.Services.Startup;
using Humaid.RiskGovernance.AdminUI.Services.Users;
using Humaid.RiskGovernance.AdminUI.Web.Auth;
using Azure.Extensions.AspNetCore.Configuration.Secrets;
using Azure.Identity;
using Azure.Monitor.OpenTelemetry.AspNetCore;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;
using OpenTelemetry;

// Every stored function returns snake_case columns (request_number, submitted_at, ...); this maps
// them onto this codebase's PascalCase model properties (RequestNumber, SubmittedAt, ...) without
// needing a column alias in every single SQL function.
Dapper.DefaultTypeMap.MatchNamesWithUnderscores = true;

// Required one-time call - QuestPDF throws at first use otherwise. Community license is free for
// this project's size (per questpdf.com/license) - US-9.3's audit export.
QuestPDF.Settings.License = QuestPDF.Infrastructure.LicenseType.Community;

var builder = WebApplication.CreateBuilder(args);

// Key Vault as a config source - added last (after CreateBuilder's own appsettings.json /
// appsettings.{Environment}.json / env var providers), so it wins for any key it holds: the
// "Key Vault, then env var, then appsettings" hierarchy DevOps asked for is just config-provider
// ordering, not custom lookup code. PEP_KEY_VAULT is already a Container App env var (and picked
// up here from the providers just built); left unset, this is a no-op - same "only activate when
// configured" pattern as every other optional integration in this codebase.
var keyVaultUri = builder.Configuration["PEP_KEY_VAULT"];
if (!string.IsNullOrWhiteSpace(keyVaultUri))
{
    // Same reasoning as BlobStorageClient.cs: ManagedIdentityCredential hard-fails (rather than
    // falling through) when IMDS is genuinely unreachable, which blocks the whole
    // DefaultAzureCredential chain on a dev machine. Can't key this off
    // IHostEnvironment/ASPNETCORE_ENVIRONMENT: the only environment deployed today (Azure
    // Container Apps dev) also sets ASPNETCORE_ENVIRONMENT=Development, identical to a
    // developer's laptop - CONTAINER_APP_NAME is what actually distinguishes them, since Azure
    // Container Apps injects it automatically into every revision and no local machine has it.
    var runningInContainerApp = !string.IsNullOrWhiteSpace(builder.Configuration["CONTAINER_APP_NAME"]);
    var keyVaultCredential = new DefaultAzureCredential(new DefaultAzureCredentialOptions
    {
        ExcludeManagedIdentityCredential = !runningInContainerApp,
    });
    try
    {
        // AddAzureKeyVault loads secrets synchronously right here (not lazily at first use), so
        // an RBAC/network problem throws immediately - caught rather than left to crash the
        // entire app (Postgres, Blob, every other unrelated feature) over one optional config
        // source. Whatever secret would have come from here just isn't in IConfiguration, so
        // downstream callers hit their normal "not configured" error at call time instead - same
        // "flag explicitly, but only when actually asked to do the thing" rule as everywhere else.
        //
        // The allow-list matters because the dev environment provisions one Key Vault shared by
        // both container apps - without it, this app would load every secret in the vault,
        // including ones that belong to Mock Systems or other infra, not just its own two.
        var workbenchKeyVaultSecretNames = new[] { "ANTHROPIC-API-KEY", "FOUNDRY-API-KEY" };
        builder.Configuration.AddAzureKeyVault(
            new Uri(keyVaultUri),
            keyVaultCredential,
            new UnderscoreKeyVaultSecretManager(workbenchKeyVaultSecretNames));
    }
    catch (Exception ex)
    {
        Console.Error.WriteLine($"Key Vault ({keyVaultUri}) could not be reached or read - continuing without it, falling back to env vars/appsettings for any key it would have provided. {ex.Message}");
    }
}

// Eagerly validates the whole DI graph (every registration below, not just whatever a given
// request happens to touch) at startup in Development - catches a missing/mistyped registration
// immediately instead of as a 500 the first time some endpoint is hit.
builder.Host.UseDefaultServiceProvider((context, options) =>
{
    options.ValidateScopes = context.HostingEnvironment.IsDevelopment();
    options.ValidateOnBuild = context.HostingEnvironment.IsDevelopment();
});

// ---------------------------------------------------------------------------
// Services
// ---------------------------------------------------------------------------

// Phase 4 - Application Insights, conditional on config being present (same "only activate when
// configured" pattern as ClaudeApiClient/BlobStorageClient) - blank locally by default so nothing
// changes for local dev and no telemetry cost is incurred until a real resource exists in Azure
// (see ops/README.md; the ~$500/month monitoring-cost concern raised on the 2026-09-09 call is
// why this stays opt-in rather than always-on). One registration auto-instruments ASP.NET Core
// requests, outbound HttpClient calls, and every existing ILogger call in this codebase - no
// per-call-site changes needed anywhere else.
var appInsightsConnectionString = builder.Configuration["APPLICATIONINSIGHTS_CONNECTION_STRING"];
if (!string.IsNullOrWhiteSpace(appInsightsConnectionString))
{
    builder.Services.AddOpenTelemetry().UseAzureMonitor(options => options.ConnectionString = appInsightsConnectionString);
}

builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddOpenApi();

// Auth0 — validates the access token the webapp obtains via Auth0 Universal Login (the SPA
// requests the "AUTH0_AUDIENCE" audience at login time; see webapp/src/auth/authConfig.js). Flat,
// screaming-snake-case keys (not nested sections) so they map directly onto Container App env vars.
var auth0Domain = builder.Configuration["AUTH0_DOMAIN"];
var auth0Audience = builder.Configuration["AUTH0_AUDIENCE"];

// No Auth0 tenant configured yet and running locally: fall back to DevBypassAuthHandler instead of
// JwtBearer, mirroring webapp/src/auth/RequireAuth.jsx's own "Auth0 not configured -> local dev
// mode" bypass. Can never activate outside Development, and never when AUTH0_DOMAIN is actually
// set - see DevBypassAuthHandler.cs.
if (string.IsNullOrWhiteSpace(auth0Domain) && builder.Environment.IsDevelopment())
{
    builder.Services
        .AddAuthentication(DevBypassAuthHandler.SchemeName)
        .AddScheme<AuthenticationSchemeOptions, DevBypassAuthHandler>(DevBypassAuthHandler.SchemeName, _ => { });
}
else
{
    builder.Services
        .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
        .AddJwtBearer(options =>
        {
            options.Authority = $"https://{auth0Domain}/";
            options.Audience = auth0Audience;
            options.TokenValidationParameters = new TokenValidationParameters
            {
                ValidateIssuer = true,
                ValidIssuer = $"https://{auth0Domain}/",
                ValidateAudience = true,
                ValidAudience = auth0Audience,
                ValidateLifetime = true,
                NameClaimType = ClaimTypes.NameIdentifier,
            };
        });
}
builder.Services.AddAuthorization();

// CORS — the webapp runs as its own Vite dev server (localhost:3000), not hosted from this API's
// wwwroot, so it needs an explicit allowed origin rather than same-origin requests.
const string WebappCorsPolicy = "WebappCorsPolicy";
builder.Services.AddCors(options => options.AddPolicy(WebappCorsPolicy, policy =>
    policy.WithOrigins(builder.Configuration.GetSection("CORS_ALLOWED_ORIGINS").Get<string[]>() ?? ["http://localhost:3000"])
          .AllowAnyMethod()
          .AllowAnyHeader()));

// Persistence — thin Dapper layer, no EF Core. Every query calls a named stored function in
// Humaid.RiskGovernance.AdminUI.DB (schema/functions/seed), never ad-hoc SQL. One repo per module,
// matching docs/architecture/architecture-mapping.md's module boundaries.
builder.Services.AddSingleton<DapperConnectionFactory>();
builder.Services.AddScoped<IChangeRequestRepo, ChangeRequestRepo>();
builder.Services.AddScoped<ICategoryMappingRepo, CategoryMappingRepo>();
builder.Services.AddScoped<IPolicyResearchRepo, PolicyResearchRepo>();
builder.Services.AddScoped<IExtractedFieldRepo, ExtractedFieldRepo>();
builder.Services.AddScoped<INarrativeSectionRepo, NarrativeSectionRepo>();
builder.Services.AddScoped<IAssessmentRepo, AssessmentRepo>();
builder.Services.AddScoped<IRiskScoreRepo, RiskScoreRepo>();
builder.Services.AddScoped<IAuditRepo, AuditRepo>();
builder.Services.AddScoped<ICommitteeRepo, CommitteeRepo>();
builder.Services.AddScoped<IWorkflowRuleRepo, WorkflowRuleRepo>();
builder.Services.AddScoped<IUserRepo, UserRepo>();
builder.Services.AddScoped<IExternalSnapshotRepo, ExternalSnapshotRepo>();

// AI orchestration - Humaid.RiskGovernance.AdminUI.AI, a sibling of .Services (see
// docs/architecture/architecture-mapping.md's mapping of CLAUDE.md's RAW.AI). Two
// IChatCompletionClient providers are registered; AI_PROVIDER picks which one the three
// AI-touchpoint clients actually receive. Anthropic direct is the default (works today);
// AzureFoundry is the team's agreed target once that project exists (2026-09-09 sync) - see
// ai/README.md. Neither provider validates its own config here - both fail loudly at call time
// (ClaudeApiClient / AzureFoundryChatCompletionClient), not silently at startup.
builder.Services.AddHttpClient("AnthropicApi", client =>
{
    var baseUrl = builder.Configuration["ANTHROPIC_API_BASE_URL"];
    client.BaseAddress = new Uri(string.IsNullOrWhiteSpace(baseUrl) ? "https://api.anthropic.com" : baseUrl);
    // Default HttpClient.Timeout (100s) is occasionally too tight for a real narrative-drafting
    // generation - observed in practice against Azure AI Foundry (evals/Program.cs hit this).
    client.Timeout = TimeSpan.FromSeconds(180);
});
builder.Services.AddHttpClient("AzureFoundry", client =>
{
    var endpoint = builder.Configuration["FOUNDRY_PROJECT_ENDPOINT"];
    if (!string.IsNullOrWhiteSpace(endpoint))
    {
        // The Azure AI Foundry portal surfaces a "project" endpoint (.../api/projects/<name>),
        // but the Model Inference API this client calls (/models/chat/completions) lives at the
        // resource root, not under that path - confirmed against a real Foundry project: the
        // project-scoped path 400s with "API version not supported", the resource root 200s.
        // Stripping a trailing /api/projects/<name> segment here means pasting either form
        // (what the portal shows, or the bare resource URL) just works, rather than this being a
        // recurring config mistake for whoever sets FOUNDRY_PROJECT_ENDPOINT next.
        var resourceRoot = System.Text.RegularExpressions.Regex.Replace(endpoint.TrimEnd('/'), @"/api/projects/[^/]+$", string.Empty);
        client.BaseAddress = new Uri(resourceRoot);
    }
    client.Timeout = TimeSpan.FromSeconds(180);
});
builder.Services.AddScoped<ClaudeApiClient>();
builder.Services.AddScoped<AzureFoundryChatCompletionClient>();
builder.Services.AddScoped<IChatCompletionClient>(sp =>
{
    var provider = builder.Configuration["AI_PROVIDER"];
    return string.Equals(provider, "AzureFoundry", StringComparison.OrdinalIgnoreCase)
        ? sp.GetRequiredService<AzureFoundryChatCompletionClient>()
        : sp.GetRequiredService<ClaudeApiClient>();
});
builder.Services.AddScoped<ICategoryMappingAiClient, CategoryMappingAiClient>();
builder.Services.AddScoped<IDocumentExtractionAiClient, DocumentExtractionAiClient>();
builder.Services.AddScoped<INarrativeDraftingAiClient, NarrativeDraftingAiClient>();

// Data Ingestion Layer (Phase 3) - the only thing allowed to call Mock Systems
// (src/6-MockExternalSystems), which is why it goes through its own named HttpClient rather than
// sharing "AnthropicApi"/"AzureFoundry" above. MOCK_SYSTEMS_BASE_URL defaults to the local dev
// port (5220) from ops/docker-compose.yml's expectations.
builder.Services.AddHttpClient("MockSystems", client =>
{
    var baseUrl = builder.Configuration["MOCK_SYSTEMS_BASE_URL"];
    client.BaseAddress = new Uri(string.IsNullOrWhiteSpace(baseUrl) ? "http://localhost:5220" : baseUrl);
});
builder.Services.AddScoped<IMockSystemsClient, MockSystemsClient>();
builder.Services.AddScoped<IDataIngestionService, DataIngestionService>();

// Real document extraction (Phase 3 Step 4) - blob storage + deterministic PDF/DOCX/XLSX
// parsing, filling in what schema/004_change_requests.sql's extracted_text column was
// deliberately left MVP-only for. BLOB_STORAGE_CONNECTION_STRING is validated at call time, not
// here - see BlobStorageClient.
builder.Services.AddScoped<IBlobStorageClient, BlobStorageClient>();
builder.Services.AddScoped<IDocumentTextExtractor, DocumentTextExtractor>();

// Business logic - one service per module.
builder.Services.AddScoped<IChangeRequestService, ChangeRequestService>();
builder.Services.AddScoped<ICategoryMappingService, CategoryMappingService>();
builder.Services.AddScoped<IPolicyResearchService, PolicyResearchService>();
builder.Services.AddScoped<IDocumentExtractionService, DocumentExtractionService>();
builder.Services.AddScoped<INarrativeService, NarrativeService>();
builder.Services.AddScoped<IAssessmentService, AssessmentService>();
builder.Services.AddScoped<IScoringService, ScoringService>();
builder.Services.AddScoped<IAuditService, AuditService>();
builder.Services.AddScoped<IAuditExportService, AuditExportService>();
builder.Services.AddScoped<ICommitteeService, CommitteeService>();
builder.Services.AddScoped<IWorkflowRuleService, WorkflowRuleService>();
builder.Services.AddScoped<IUserService, UserService>();

var app = builder.Build();

// ---------------------------------------------------------------------------
// HTTP pipeline
// ---------------------------------------------------------------------------

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
    // Interactive UI over the same OpenAPI doc above - lets a developer call any real endpoint
    // (e.g. POST /api/ChangeRequest/Submit) directly, through the same controller/service/stored-
    // function path the webapp uses, so demo/test data gets a real audit trail. Never mount this
    // outside Development - it's a way to exercise the API, not a bypass of it, and it has no
    // reason to be reachable once a real Auth0 tenant is configured.
    app.UseSwaggerUI(options =>
    {
        options.SwaggerEndpoint("/openapi/v1.json", "Humaid.RiskGovernance.AdminUI.Web v1");
        options.RoutePrefix = "swagger";
    });
}

// Serves the webapp's production build (index.html, assets — copied into wwwroot by the
// Dockerfile's node stage) when deployed as a single container. Harmless locally: wwwroot doesn't
// exist in local dev, where the webapp instead runs as its own Vite dev server on :3000 and CORS
// (below) is what makes that separate-origin setup work.
app.UseDefaultFiles();
app.UseStaticFiles();

app.UseCors(WebappCorsPolicy);
app.UseAuthentication();
app.UseAuthorization();

app.MapControllers();

app.Run();
