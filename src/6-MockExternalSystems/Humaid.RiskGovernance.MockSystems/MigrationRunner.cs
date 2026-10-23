using System.Text.RegularExpressions;
using Npgsql;

namespace Humaid.RiskGovernance.MockSystems;

/// <summary>
/// Applies db/schema.sql, db/functions/**, and db/seed.sql to whichever database the service's
/// connection string points at, at startup and before the host accepts requests - replacing the
/// manual `psql -f deploy_all.sql` step, which nobody had run against Azure (the product dropdown
/// came back empty because func_listProducts() did not exist).
/// <para>
/// Every file is idempotent by construction - tables are CREATE ... IF NOT EXISTS, functions are
/// CREATE OR REPLACE, seed rows are INSERT ... ON CONFLICT DO NOTHING - so unlike the Workbench's
/// runner there is no baseline-vs-delta split and no tracking table: all three are simply applied
/// on every start. A second run changes nothing, and never resets a risk flag the Workbench's
/// feedback loop has written back (seed rows are only inserted when absent).
/// </para>
/// </summary>
public sealed class MigrationRunner(NpgsqlDataSource dataSource, string dbFolderPath, ILogger<MigrationRunner> logger)
{
    private const string AdvisoryLockKey = "humaid_mock_systems_db_migrations";

    private static readonly Regex FunctionNamePattern =
        new(@"CREATE\s+OR\s+REPLACE\s+FUNCTION\s+(\w+)\s*\(", RegexOptions.IgnoreCase | RegexOptions.Compiled);

    public async Task RunAsync(CancellationToken ct = default)
    {
        await using var conn = await dataSource.OpenConnectionAsync(ct).ConfigureAwait(false);

        // Container Apps can run more than one replica; serialise concurrent startups instead of
        // racing two CREATE statements against each other. Session-scoped, held for this run.
        await ExecuteAsync(conn, $"SELECT pg_advisory_lock(hashtext('{AdvisoryLockKey}'))", ct).ConfigureAwait(false);
        try
        {
            await ApplyFileAsync(conn, Path.Combine(dbFolderPath, "schema.sql"), ct).ConfigureAwait(false);
            foreach (var file in ListSqlFiles(Path.Combine(dbFolderPath, "functions")))
            {
                await ApplyFileAsync(conn, file, ct).ConfigureAwait(false);
            }
            await ApplyFileAsync(conn, Path.Combine(dbFolderPath, "seed.sql"), ct).ConfigureAwait(false);

            await LogPostDeploySummaryAsync(conn, ct).ConfigureAwait(false);
        }
        finally
        {
            await ExecuteAsync(conn, $"SELECT pg_advisory_unlock(hashtext('{AdvisoryLockKey}'))", ct).ConfigureAwait(false);
        }
    }

    /// <summary>
    /// One file, one transaction. Postgres's 42P13 ("cannot change return type of existing
    /// function") is the one thing CREATE OR REPLACE cannot do in place, so a function whose
    /// RETURNS shape changed is dropped and recreated rather than needing a hand-run step - the
    /// same handling the Workbench's runner has.
    /// </summary>
    private async Task ApplyFileAsync(NpgsqlConnection conn, string path, CancellationToken ct)
    {
        var sql = await File.ReadAllTextAsync(path, ct).ConfigureAwait(false);
        try
        {
            await ExecuteInTransactionAsync(conn, sql, ct).ConfigureAwait(false);
        }
        catch (PostgresException ex) when (ex.SqlState == PostgresErrorCodes.InvalidFunctionDefinition
                                           && FunctionNamePattern.Match(sql) is { Success: true } match)
        {
            var functionName = match.Groups[1].Value;
            logger.LogInformation("{Function} changed its return shape - dropping and recreating.", functionName);
            await ExecuteAsync(conn, $"DROP FUNCTION IF EXISTS {functionName}", ct).ConfigureAwait(false);
            await ExecuteInTransactionAsync(conn, sql, ct).ConfigureAwait(false);
        }
        catch (PostgresException ex)
        {
            // Halt startup rather than serve against a half-applied schema - the exception
            // propagates out of RunAsync and Program.cs does not catch it.
            throw new InvalidOperationException($"Failed applying '{Path.GetFileName(path)}': {ex.MessageText}", ex);
        }
    }

    private static async Task ExecuteInTransactionAsync(NpgsqlConnection conn, string sql, CancellationToken ct)
    {
        await using var tx = await conn.BeginTransactionAsync(ct).ConfigureAwait(false);
        try
        {
            await using var cmd = new NpgsqlCommand(sql, conn, tx) { CommandTimeout = 120 };
            await cmd.ExecuteNonQueryAsync(ct).ConfigureAwait(false);
            await tx.CommitAsync(ct).ConfigureAwait(false);
        }
        catch
        {
            await tx.RollbackAsync(CancellationToken.None).ConfigureAwait(false);
            throw;
        }
    }

    private static IReadOnlyList<string> ListSqlFiles(string folder)
    {
        if (!Directory.Exists(folder))
        {
            return [];
        }
        var files = Directory.GetFiles(folder, "*.sql", SearchOption.AllDirectories);
        Array.Sort(files, StringComparer.Ordinal);
        return files;
    }

    private static async Task ExecuteAsync(NpgsqlConnection conn, string sql, CancellationToken ct)
    {
        await using var cmd = new NpgsqlCommand(sql, conn);
        await cmd.ExecuteNonQueryAsync(ct).ConfigureAwait(false);
    }

    private async Task LogPostDeploySummaryAsync(NpgsqlConnection conn, CancellationToken ct)
    {
        await using var cmd = new NpgsqlCommand(
            "SELECT (SELECT count(*) FROM mock_systems.crm_customer), " +
            "(SELECT count(*) FROM mock_systems.core_banking_product), " +
            "(SELECT count(*) FROM mock_systems.vendor_registry)", conn);
        await using var reader = await cmd.ExecuteReaderAsync(ct).ConfigureAwait(false);
        if (await reader.ReadAsync(ct).ConfigureAwait(false))
        {
            logger.LogInformation(
                "Mock Systems post-deploy check: {Customers} customers, {Products} products, {Vendors} vendors",
                reader.GetInt64(0), reader.GetInt64(1), reader.GetInt64(2));
        }
    }
}
