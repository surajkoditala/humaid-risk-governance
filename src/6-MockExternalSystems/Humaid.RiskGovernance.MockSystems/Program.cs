using Azure.Core;
using Azure.Extensions.AspNetCore.Configuration.Secrets;
using Azure.Identity;
using Azure.Monitor.OpenTelemetry.AspNetCore;
using Dapper;
using Humaid.RiskGovernance.MockSystems;
using Npgsql;
using OpenTelemetry;

Dapper.DefaultTypeMap.MatchNamesWithUnderscores = true;

var builder = WebApplication.CreateBuilder(args);

// Key Vault as a config source - same pattern and reasoning as the Workbench's Program.cs
// (highest-priority provider, no-op when PEP_KEY_VAULT is unset).
var keyVaultUri = builder.Configuration["PEP_KEY_VAULT"];
if (!string.IsNullOrWhiteSpace(keyVaultUri))
{
    var keyVaultCredential = new DefaultAzureCredential(new DefaultAzureCredentialOptions
    {
        ExcludeManagedIdentityCredential = !builder.Environment.IsProduction(),
    });
    try
    {
        // See the Workbench's Program.cs - AddAzureKeyVault loads synchronously, so a failure
        // here is caught rather than left to crash the whole app over one optional config source.
        builder.Configuration.AddAzureKeyVault(new Uri(keyVaultUri), keyVaultCredential, new UnderscoreKeyVaultSecretManager());
    }
    catch (Exception ex)
    {
        Console.Error.WriteLine($"Key Vault ({keyVaultUri}) could not be reached or read - continuing without it, falling back to env vars/appsettings for any key it would have provided. {ex.Message}");
    }
}

builder.Services.AddOpenApi();

// Phase 4 - same conditional-on-config Application Insights registration as the Workbench's own
// Program.cs - see the comment there.
var appInsightsConnectionString = builder.Configuration["APPLICATIONINSIGHTS_CONNECTION_STRING"];
if (!string.IsNullOrWhiteSpace(appInsightsConnectionString))
{
    builder.Services.AddOpenTelemetry().UseAzureMonitor(options => options.ConnectionString = appInsightsConnectionString);
}

// MOCK_SYSTEMS_POSTGRESQL_CONNECTIONSTRING is the primary key (password auth, matches local dev's
// Azurite-equivalent flow); AZURE_POSTGRESQL_ENDPOINT is a fallback - the same connection-string
// shape but without a password (Server/Database/Port/Ssl Mode/User Id), for Managed Identity
// (Entra ID) auth against the shared Flexible Server - same dual-mode pattern as the Workbench's
// own DapperConnectionFactory.cs, reused here rather than adding a second env var Suraj would need
// to provision separately.
var connectionString = builder.Configuration["MOCK_SYSTEMS_POSTGRESQL_CONNECTIONSTRING"];
if (string.IsNullOrWhiteSpace(connectionString))
{
    connectionString = builder.Configuration["AZURE_POSTGRESQL_ENDPOINT"];
}
if (string.IsNullOrWhiteSpace(connectionString))
{
    throw new InvalidOperationException(
        "Neither MOCK_SYSTEMS_POSTGRESQL_CONNECTIONSTRING nor AZURE_POSTGRESQL_ENDPOINT is configured.");
}

var pgConnStringBuilder = new NpgsqlConnectionStringBuilder(connectionString);
var useEntraIdAuth = !string.IsNullOrEmpty(pgConnStringBuilder.Username) && string.IsNullOrEmpty(pgConnStringBuilder.Password);

var dataSourceBuilder = new NpgsqlDataSourceBuilder(pgConnStringBuilder.ConnectionString);
if (useEntraIdAuth)
{
    var credential = new DefaultAzureCredential();
    dataSourceBuilder.UsePeriodicPasswordProvider(
        async (_, ct) =>
        {
            var token = await credential
                .GetTokenAsync(new TokenRequestContext(["https://ossrdbms-aad.database.windows.net/.default"]), ct)
                .ConfigureAwait(false);
            return token.Token;
        },
        TimeSpan.FromMinutes(55),
        TimeSpan.FromSeconds(30));
}
var dataSource = dataSourceBuilder.Build();
builder.Services.AddSingleton(dataSource);

var corsOrigins = builder.Configuration.GetSection("CORS_ALLOWED_ORIGINS").Get<string[]>() ?? [];
builder.Services.AddCors(options => options.AddDefaultPolicy(policy =>
{
    if (corsOrigins.Length > 0) policy.WithOrigins(corsOrigins).AllowAnyHeader().AllowAnyMethod();
}));

var app = builder.Build();
if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
    app.UseSwaggerUI(options =>
    {
        options.SwaggerEndpoint("/openapi/v1.json", "Humaid.RiskGovernance.MockSystems v1");
        options.RoutePrefix = "swagger";
    });
}
app.UseCors();

// Every query below calls a named SQL function (db/functions/) - no ad-hoc SQL, same convention
// the Workbench's own DB layer follows throughout (see docs/architecture/architecture-mapping.md).

// --- Customers (Mock CRM) --------------------------------------------------------------------
app.MapGet("/api/customers", async (NpgsqlDataSource db) =>
{
    await using var conn = await db.OpenConnectionAsync();
    return await conn.QueryAsync<MockCustomer>("SELECT * FROM func_listCustomers()");
});

app.MapGet("/api/customers/{id:guid}", async (Guid id, NpgsqlDataSource db) =>
{
    await using var conn = await db.OpenConnectionAsync();
    var customer = await conn.QuerySingleOrDefaultAsync<MockCustomer>("SELECT * FROM func_getCustomerById(@id)", new { id });
    return customer is null ? Results.NotFound() : Results.Ok(customer);
});

app.MapPost("/api/customers/{id:guid}/risk-flag", async (Guid id, CustomerRiskFlagInput input, NpgsqlDataSource db) =>
{
    await using var conn = await db.OpenConnectionAsync();
    var updatedId = await conn.QuerySingleOrDefaultAsync<Guid?>(
        "SELECT * FROM func_updateCustomerRiskFlag(@id, @riskFlag)", new { id, riskFlag = input.RiskFlag });
    return updatedId is null ? Results.NotFound() : Results.NoContent();
});

// --- Products (Mock Core Banking) -------------------------------------------------------------
app.MapGet("/api/products", async (NpgsqlDataSource db) =>
{
    await using var conn = await db.OpenConnectionAsync();
    return await conn.QueryAsync<MockProduct>("SELECT * FROM func_listProducts()");
});

app.MapGet("/api/products/{id:guid}", async (Guid id, NpgsqlDataSource db) =>
{
    await using var conn = await db.OpenConnectionAsync();
    var product = await conn.QuerySingleOrDefaultAsync<MockProduct>("SELECT * FROM func_getProductById(@id)", new { id });
    return product is null ? Results.NotFound() : Results.Ok(product);
});

app.MapPost("/api/products/{id:guid}/risk-flag", async (Guid id, ProductRiskUpdateInput input, NpgsqlDataSource db) =>
{
    await using var conn = await db.OpenConnectionAsync();
    var updatedId = await conn.QuerySingleOrDefaultAsync<Guid?>(
        "SELECT * FROM func_updateProductRiskRating(@id, @goLive, @riskRating)", new { id, input.GoLive, input.RiskRating });
    return updatedId is null ? Results.NotFound() : Results.NoContent();
});

// --- Vendors (Mock Vendor Management) -----------------------------------------------------------
app.MapGet("/api/vendors", async (NpgsqlDataSource db) =>
{
    await using var conn = await db.OpenConnectionAsync();
    return await conn.QueryAsync<MockVendor>("SELECT * FROM func_listVendors()");
});

app.MapGet("/api/vendors/{id:guid}", async (Guid id, NpgsqlDataSource db) =>
{
    await using var conn = await db.OpenConnectionAsync();
    var vendor = await conn.QuerySingleOrDefaultAsync<MockVendor>("SELECT * FROM func_getVendorById(@id)", new { id });
    return vendor is null ? Results.NotFound() : Results.Ok(vendor);
});

app.MapPost("/api/vendors/{id:guid}/risk-flag", async (Guid id, VendorRiskUpdateInput input, NpgsqlDataSource db) =>
{
    await using var conn = await db.OpenConnectionAsync();
    var updatedId = await conn.QuerySingleOrDefaultAsync<Guid?>(
        "SELECT * FROM func_updateVendorRiskRating(@id, @updatedRiskRating)", new { id, input.UpdatedRiskRating });
    return updatedId is null ? Results.NotFound() : Results.NoContent();
});

app.MapGet("/api/ping", () => Results.Ok("pong"));

app.Run();

// Key Vault secret names use hyphens; every config key this app reads uses screaming-snake-case
// with underscores so it maps directly onto Container App env vars too - see the Workbench's
// Program.cs for the fuller comment.
public class UnderscoreKeyVaultSecretManager : KeyVaultSecretManager
{
    public override string GetKey(Azure.Security.KeyVault.Secrets.KeyVaultSecret secret) => secret.Name.Replace('-', '_');
}
