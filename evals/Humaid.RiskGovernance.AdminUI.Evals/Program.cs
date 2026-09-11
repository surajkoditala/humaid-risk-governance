using System.Text.Json;
using System.Text.Json.Serialization;
using Humaid.RiskGovernance.AdminUI.AI;
using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Ai;
using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Ai;
using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.RiskFramework;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

// Evaluation framework (Phase 3 Step 6) - see evals/README.md for methodology. Config comes from
// environment variables only (ANTHROPIC_API_KEY, ANTHROPIC_MODEL, AI_PROVIDER, FOUNDRY_*) - no
// secrets file to keep in sync with src/1-API's appsettings.Development.json; export the same
// values before running this.

var jsonOptions = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
var datasetsDir = Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "datasets");
if (!Directory.Exists(datasetsDir))
{
    // Fallback for `dotnet run` from the evals/Humaid.RiskGovernance.AdminUI.Evals/ folder itself.
    datasetsDir = Path.Combine(Directory.GetCurrentDirectory(), "..", "datasets");
}

var configuration = new ConfigurationBuilder().AddEnvironmentVariables().Build();

var services = new ServiceCollection();
services.AddSingleton<IConfiguration>(configuration);
services.AddLogging(b => b.AddConsole().SetMinimumLevel(LogLevel.Warning));

// Mirrors src/1-API/Humaid.RiskGovernance.AdminUI.Web/Program.cs's AI registration exactly - same
// provider switch, same client types, so this harness evaluates the real production wiring.
services.AddHttpClient("AnthropicApi", client =>
{
    var baseUrl = configuration["ANTHROPIC_API_BASE_URL"];
    client.BaseAddress = new Uri(string.IsNullOrWhiteSpace(baseUrl) ? "https://api.anthropic.com" : baseUrl);
    client.Timeout = TimeSpan.FromSeconds(180);
});
services.AddHttpClient("AzureFoundry", client =>
{
    var endpoint = configuration["FOUNDRY_PROJECT_ENDPOINT"];
    if (!string.IsNullOrWhiteSpace(endpoint))
    {
        // Mirrors src/1-API/Humaid.RiskGovernance.AdminUI.Web/Program.cs's same normalization -
        // see that file's comment for why (the Foundry portal's "project" endpoint isn't the
        // Model Inference API's actual base URL).
        var resourceRoot = System.Text.RegularExpressions.Regex.Replace(endpoint.TrimEnd('/'), @"/api/projects/[^/]+$", string.Empty);
        client.BaseAddress = new Uri(resourceRoot);
    }
    client.Timeout = TimeSpan.FromSeconds(180);
});
services.AddScoped<ClaudeApiClient>();
services.AddScoped<AzureFoundryChatCompletionClient>();
services.AddScoped<IChatCompletionClient>(sp =>
{
    var provider = configuration["AI_PROVIDER"];
    return string.Equals(provider, "AzureFoundry", StringComparison.OrdinalIgnoreCase)
        ? sp.GetRequiredService<AzureFoundryChatCompletionClient>()
        : sp.GetRequiredService<ClaudeApiClient>();
});
services.AddScoped<ICategoryMappingAiClient, CategoryMappingAiClient>();
services.AddScoped<IDocumentExtractionAiClient, DocumentExtractionAiClient>();
services.AddScoped<INarrativeDraftingAiClient, NarrativeDraftingAiClient>();

await using var provider = services.BuildServiceProvider();
using var scope = provider.CreateScope();
var sp = scope.ServiceProvider;

var results = new List<EvalResult>();

await RunCategoryMappingSuiteAsync(sp.GetRequiredService<ICategoryMappingAiClient>(), datasetsDir, jsonOptions, results);
await RunDocumentExtractionSuiteAsync(sp.GetRequiredService<IDocumentExtractionAiClient>(), datasetsDir, jsonOptions, results);
await RunNarrativeSuiteAsync(sp.GetRequiredService<INarrativeDraftingAiClient>(), datasetsDir, jsonOptions, results);

PrintTable(results);
WriteReport(results, datasetsDir);

var failCount = results.Count(r => r.Outcome is Outcome.Fail or Outcome.Error);
Environment.Exit(failCount > 0 ? 1 : 0);

// ---- Suites ------------------------------------------------------------------------------------

static async Task RunCategoryMappingSuiteAsync(ICategoryMappingAiClient client, string datasetsDir, JsonSerializerOptions jsonOptions, List<EvalResult> results)
{
    var cases = JsonSerializer.Deserialize<List<CategoryMappingCase>>(
        await File.ReadAllTextAsync(Path.Combine(datasetsDir, "category_mapping.json")), jsonOptions) ?? [];

    foreach (var c in cases)
    {
        try
        {
            var defaults = c.AllowedCategories.Select(a => new ChangeTypeCategoryDefault
            {
                RiskCategoryId = a.RiskCategoryId,
                Code = a.Code,
                CitationSection = a.CitationSection,
                Weight = "Primary",
            }).ToList();

            var proposals = await client.ProposeAsync(c.ChangeType, c.Title, c.DescriptionText, defaults);
            var proposedCodes = proposals.Select(p => p.CategoryCode).ToHashSet(StringComparer.OrdinalIgnoreCase);
            var expected = c.ExpectedCategoryCodes.ToHashSet(StringComparer.OrdinalIgnoreCase);

            // Set-overlap, not exact-set-equality: proposing a plausible Secondary category
            // alongside the expected Primary one is acceptable (the change-type defaults
            // themselves encode Primary/Secondary weight), missing the expected category or
            // inventing one outside the allowed list is not.
            var missingExpected = expected.Except(proposedCodes).ToList();
            var fabricated = proposedCodes.Except(defaults.Select(d => d.Code), StringComparer.OrdinalIgnoreCase).ToList();

            if (missingExpected.Count == 0 && fabricated.Count == 0)
            {
                results.Add(EvalResult.Pass("CategoryMapping", c.Id, c.Description, $"proposed [{string.Join(", ", proposedCodes)}]"));
            }
            else
            {
                var detail = new List<string>();
                if (missingExpected.Count > 0) detail.Add($"missing expected: [{string.Join(", ", missingExpected)}]");
                if (fabricated.Count > 0) detail.Add($"fabricated (not in allowed list): [{string.Join(", ", fabricated)}]");
                results.Add(EvalResult.Fail("CategoryMapping", c.Id, c.Description, string.Join("; ", detail)));
            }
        }
        catch (InvalidOperationException ex) when (ex.Message.Contains("not configured", StringComparison.OrdinalIgnoreCase))
        {
            results.Add(EvalResult.Skip("CategoryMapping", c.Id, c.Description, "AI provider not configured"));
        }
        catch (Exception ex)
        {
            // A transient network/timeout failure on one case must not take down the whole run -
            // the point of an eval harness is to keep going and report what it could, not crash
            // and lose every result gathered so far (this caught a real bug: a Foundry call that
            // exceeded the default 100s HttpClient timeout used to kill the entire process).
            results.Add(EvalResult.Error("CategoryMapping", c.Id, c.Description, $"{ex.GetType().Name}: {ex.Message}"));
        }
    }
}

static async Task RunDocumentExtractionSuiteAsync(IDocumentExtractionAiClient client, string datasetsDir, JsonSerializerOptions jsonOptions, List<EvalResult> results)
{
    var cases = JsonSerializer.Deserialize<List<DocumentExtractionCase>>(
        await File.ReadAllTextAsync(Path.Combine(datasetsDir, "document_extraction.json")), jsonOptions) ?? [];

    foreach (var c in cases)
    {
        try
        {
            var fields = await client.ExtractAsync(c.ChangeType, c.DocumentText);
            var byKey = fields.ToDictionary(f => f.FieldKey, StringComparer.OrdinalIgnoreCase);
            var problems = new List<string>();

            if (c.ExpectEmptyResult == true && fields.Count > 0)
            {
                problems.Add($"expected an empty result, got {fields.Count} field(s)");
            }

            foreach (var (key, expectedValue) in c.ExpectedFields)
            {
                if (!byKey.TryGetValue(key, out var field) || field.FieldValue is null ||
                    !field.FieldValue.Contains(expectedValue, StringComparison.OrdinalIgnoreCase))
                {
                    problems.Add($"'{key}' expected to contain '{expectedValue}', got '{(byKey.TryGetValue(key, out var f) ? f.FieldValue : "(missing)")}'");
                }
            }
            foreach (var key in c.FieldsThatMustNotNeedReview ?? [])
            {
                if (byKey.TryGetValue(key, out var field) && field.NeedsReview)
                {
                    problems.Add($"'{key}' should not be flagged needsReview, but was");
                }
            }
            foreach (var key in c.FieldsThatMustNeedReview ?? [])
            {
                if (!byKey.TryGetValue(key, out var field))
                {
                    problems.Add($"'{key}' expected to be extracted (flagged needsReview), but was not returned at all");
                }
                else if (!field.NeedsReview)
                {
                    problems.Add($"'{key}' should be flagged needsReview given the ambiguous source text, but was not");
                }
            }

            results.Add(problems.Count == 0
                ? EvalResult.Pass("DocumentExtraction", c.Id, c.Description, $"{fields.Count} field(s) extracted as expected")
                : EvalResult.Fail("DocumentExtraction", c.Id, c.Description, string.Join("; ", problems)));
        }
        catch (InvalidOperationException ex) when (ex.Message.Contains("not configured", StringComparison.OrdinalIgnoreCase))
        {
            results.Add(EvalResult.Skip("DocumentExtraction", c.Id, c.Description, "AI provider not configured"));
        }
        catch (Exception ex)
        {
            results.Add(EvalResult.Error("DocumentExtraction", c.Id, c.Description, $"{ex.GetType().Name}: {ex.Message}"));
        }
    }
}

static async Task RunNarrativeSuiteAsync(INarrativeDraftingAiClient client, string datasetsDir, JsonSerializerOptions jsonOptions, List<EvalResult> results)
{
    var cases = JsonSerializer.Deserialize<List<NarrativeCase>>(
        await File.ReadAllTextAsync(Path.Combine(datasetsDir, "narrative.json")), jsonOptions) ?? [];

    foreach (var c in cases)
    {
        var input = new NarrativeDraftInput
        {
            ChangeType = c.ChangeType,
            ChangeTitle = c.ChangeTitle,
            ChangeDescription = c.ChangeDescription,
            RiskCategoryId = c.RiskCategoryId,
            CategoryName = c.CategoryName,
            CategoryCitation = c.CategoryCitation,
            ReliedUponPolicyExcerpts = c.ReliedUponPolicyExcerpts,
            ExtractedFieldFacts = c.ExtractedFieldFacts,
        };

        try
        {
            switch (c.CheckType)
            {
                case "citation_presence":
                {
                    var draft = await client.DraftAsync(input);
                    var hit = (c.CitationPresenceKeywords ?? []).Any(k => draft.NarrativeText.Contains(k, StringComparison.OrdinalIgnoreCase));
                    results.Add(hit
                        ? EvalResult.Pass("Narrative", c.Id, c.Description, "narrative references the supplied grounding (proxy check)")
                        : EvalResult.Fail("Narrative", c.Id, c.Description, $"narrative did not mention any of [{string.Join(", ", c.CitationPresenceKeywords ?? [])}]"));
                    break;
                }
                case "well_formed":
                {
                    var draft = await client.DraftAsync(input);
                    // Proxy only, by design - see evals/README.md's "what narrative scoring does
                    // NOT verify". A non-empty, parseable response is what's checked here.
                    results.Add(!string.IsNullOrWhiteSpace(draft.NarrativeText)
                        ? EvalResult.Pass("Narrative", c.Id, c.Description, "well-formed non-empty narrative (fabrication NOT independently verified - proxy limitation)")
                        : EvalResult.Fail("Narrative", c.Id, c.Description, "narrative was empty"));
                    break;
                }
                case "regeneration_keyword":
                {
                    input.RegenerationFeedback = c.RegenerationFeedback;
                    var regenerated = await client.DraftAsync(input);
                    var keyword = c.ExpectedRegenerationKeyword ?? string.Empty;
                    results.Add(regenerated.NarrativeText.Contains(keyword, StringComparison.OrdinalIgnoreCase)
                        ? EvalResult.Pass("Narrative", c.Id, c.Description, $"regenerated narrative incorporates feedback keyword '{keyword}'")
                        : EvalResult.Fail("Narrative", c.Id, c.Description, $"regenerated narrative did not mention feedback keyword '{keyword}'"));
                    break;
                }
                default:
                    results.Add(EvalResult.Fail("Narrative", c.Id, c.Description, $"unknown checkType '{c.CheckType}'"));
                    break;
            }
        }
        catch (InvalidOperationException ex) when (ex.Message.Contains("not configured", StringComparison.OrdinalIgnoreCase))
        {
            results.Add(EvalResult.Skip("Narrative", c.Id, c.Description, "AI provider not configured"));
        }
        catch (Exception ex)
        {
            results.Add(EvalResult.Error("Narrative", c.Id, c.Description, $"{ex.GetType().Name}: {ex.Message}"));
        }
    }
}

// ---- Reporting -----------------------------------------------------------------------------------

static void PrintTable(List<EvalResult> results)
{
    Console.WriteLine();
    Console.WriteLine($"{"Suite",-18} {"Case",-32} {"Outcome",-8} Detail");
    Console.WriteLine(new string('-', 100));
    foreach (var r in results)
    {
        Console.WriteLine($"{r.Suite,-18} {r.CaseId,-32} {r.Outcome,-8} {r.Detail}");
    }
    Console.WriteLine(new string('-', 100));

    var pass = results.Count(r => r.Outcome == Outcome.Pass);
    var fail = results.Count(r => r.Outcome == Outcome.Fail);
    var skip = results.Count(r => r.Outcome == Outcome.Skip);
    var error = results.Count(r => r.Outcome == Outcome.Error);
    Console.WriteLine($"Total: {results.Count}   Pass: {pass}   Fail: {fail}   Skipped: {skip}   Error: {error}");
    if (skip > 0)
    {
        Console.WriteLine("(Skipped cases need AI_PROVIDER configured with a real key/endpoint - see evals/README.md.)");
    }
    if (error > 0)
    {
        Console.WriteLine("(Error cases mean the call itself didn't complete - e.g. a network timeout - not that the model's answer was wrong. Re-run to distinguish a flaky network blip from something worth investigating.)");
    }
}

static void WriteReport(List<EvalResult> results, string datasetsDir)
{
    var reportPath = Path.Combine(datasetsDir, "..", "results", $"eval-run-{DateTime.UtcNow:yyyyMMdd-HHmmss}.md");
    Directory.CreateDirectory(Path.GetDirectoryName(reportPath)!);

    var pass = results.Count(r => r.Outcome == Outcome.Pass);
    var fail = results.Count(r => r.Outcome == Outcome.Fail);
    var skip = results.Count(r => r.Outcome == Outcome.Skip);
    var error = results.Count(r => r.Outcome == Outcome.Error);

    using var writer = new StreamWriter(reportPath);
    writer.WriteLine($"# Eval run - {DateTime.UtcNow:yyyy-MM-dd HH:mm:ss} UTC");
    writer.WriteLine();
    writer.WriteLine($"**Total: {results.Count} · Pass: {pass} · Fail: {fail} · Skipped: {skip} · Error: {error}**");
    writer.WriteLine();
    writer.WriteLine("| Suite | Case | Outcome | Detail |");
    writer.WriteLine("|---|---|---|---|");
    foreach (var r in results)
    {
        writer.WriteLine($"| {r.Suite} | {r.CaseId} | {r.Outcome} | {r.Detail.Replace("|", "\\|")} |");
    }

    Console.WriteLine();
    Console.WriteLine($"Report written to {Path.GetFullPath(reportPath)}");
}

// ---- Types -----------------------------------------------------------------------------------

internal enum Outcome { Pass, Fail, Skip, Error }

internal record EvalResult(string Suite, string CaseId, string Detail, Outcome Outcome)
{
    public static EvalResult Pass(string suite, string caseId, string description, string detail) => new(suite, caseId, detail, Outcome.Pass);
    public static EvalResult Fail(string suite, string caseId, string description, string detail) => new(suite, caseId, detail, Outcome.Fail);
    public static EvalResult Skip(string suite, string caseId, string description, string detail) => new(suite, caseId, detail, Outcome.Skip);
    public static EvalResult Error(string suite, string caseId, string description, string detail) => new(suite, caseId, detail, Outcome.Error);
}

internal class CategoryMappingCase
{
    public string Id { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public string ChangeType { get; set; } = string.Empty;
    public string Title { get; set; } = string.Empty;
    [JsonPropertyName("description_text")] public string DescriptionText { get; set; } = string.Empty;
    public List<AllowedCategoryDto> AllowedCategories { get; set; } = [];
    public List<string> ExpectedCategoryCodes { get; set; } = [];
}

internal class AllowedCategoryDto
{
    public Guid RiskCategoryId { get; set; }
    public string Code { get; set; } = string.Empty;
    public string CitationSection { get; set; } = string.Empty;
}

internal class DocumentExtractionCase
{
    public string Id { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public string ChangeType { get; set; } = string.Empty;
    public string DocumentText { get; set; } = string.Empty;
    public Dictionary<string, string> ExpectedFields { get; set; } = [];
    public List<string>? FieldsThatMustNotNeedReview { get; set; }
    public List<string>? FieldsThatMustNeedReview { get; set; }
    public bool? ExpectEmptyResult { get; set; }
}

internal class NarrativeCase
{
    public string Id { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public string CheckType { get; set; } = string.Empty;
    public string ChangeType { get; set; } = string.Empty;
    public string ChangeTitle { get; set; } = string.Empty;
    public string ChangeDescription { get; set; } = string.Empty;
    public Guid RiskCategoryId { get; set; }
    public string CategoryName { get; set; } = string.Empty;
    public string CategoryCitation { get; set; } = string.Empty;
    public List<string> ReliedUponPolicyExcerpts { get; set; } = [];
    public List<string> ExtractedFieldFacts { get; set; } = [];
    public List<string>? CitationPresenceKeywords { get; set; }
    public string? RegenerationFeedback { get; set; }
    public string? ExpectedRegenerationKeyword { get; set; }
}
