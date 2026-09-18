using Azure.Monitor.OpenTelemetry.AspNetCore;
using Dapper;
using Humaid.RiskGovernance.MockSystems;
using Npgsql;
using OpenTelemetry;

Dapper.DefaultTypeMap.MatchNamesWithUnderscores = true;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddOpenApi();

// Phase 4 - same conditional-on-config Application Insights registration as the Workbench's own
// Program.cs - see the comment there.
var appInsightsConnectionString = builder.Configuration["APPLICATIONINSIGHTS_CONNECTION_STRING"];
if (!string.IsNullOrWhiteSpace(appInsightsConnectionString))
{
    builder.Services.AddOpenTelemetry().UseAzureMonitor(options => options.ConnectionString = appInsightsConnectionString);
}

var connectionString = builder.Configuration["MOCK_SYSTEMS_POSTGRESQL_CONNECTIONSTRING"]
    ?? throw new InvalidOperationException("MOCK_SYSTEMS_POSTGRESQL_CONNECTIONSTRING is not configured.");
var dataSource = NpgsqlDataSource.Create(connectionString);
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
