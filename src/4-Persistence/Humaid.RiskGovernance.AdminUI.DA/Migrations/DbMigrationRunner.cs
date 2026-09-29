namespace Humaid.RiskGovernance.AdminUI.DA.Migrations
{
    using System.Text.RegularExpressions;
    using Microsoft.Extensions.Logging;
    using Npgsql;

    /// <summary>
    /// US-12.1 / DEF-007: applies Humaid.RiskGovernance.AdminUI.DB's schema, functions, and seed
    /// data to whichever database <see cref="DapperConnectionFactory"/> points at, replacing the
    /// manual one-shot psql/deploy_all.sql steps documented in that folder's README.md. Runs once
    /// at application startup, before the host starts accepting requests (see Program.cs).
    /// <para>
    /// An empty database (no application tables yet) gets the full current-state snapshot,
    /// <c>deploy_all.sql</c>, unchanged from today's one-shot behaviour. An already-provisioned
    /// database only receives whichever <c>migrations/*.sql</c> files it hasn't seen yet - each
    /// one a forward-only delta, tracked by filename in <c>schema_migrations</c>, applied in its
    /// own transaction so a failure reports exactly which file broke and never leaves the schema
    /// half-migrated (US-12.1 AC3). <c>functions/**/*.sql</c> (CREATE OR REPLACE) and
    /// <c>seed/*.sql</c> (INSERT ... ON CONFLICT DO NOTHING) are idempotent by construction, so
    /// both are simply re-applied on every startup rather than tracked - a function fix or a new
    /// seed row reaches an already-provisioned database without needing its own numbered migration
    /// file (US-12.1 AC2: a second run is a safe no-op and destroys no data).
    /// </para>
    /// </summary>
    public sealed class DbMigrationRunner
    {
        private const string AdvisoryLockKey = "humaid_risk_governance_db_migrations";

        private readonly DapperConnectionFactory _connectionFactory;
        private readonly string _dbFolderPath;
        private readonly ILogger<DbMigrationRunner> _logger;

        public DbMigrationRunner(DapperConnectionFactory connectionFactory, string dbFolderPath, ILogger<DbMigrationRunner> logger)
        {
            _connectionFactory = connectionFactory;
            _dbFolderPath = dbFolderPath;
            _logger = logger;
        }

        public async Task RunAsync(CancellationToken ct = default)
        {
            await using var conn = await _connectionFactory.OpenAsync(ct).ConfigureAwait(false);

            // Container Apps can scale to more than one replica; this serializes concurrent
            // migration attempts across them instead of racing two ALTER TABLEs against each
            // other. Session-scoped (not pg_advisory_xact_lock), held for this whole run on this
            // one connection.
            await ExecuteAsync(conn, $"SELECT pg_advisory_lock(hashtext('{AdvisoryLockKey}'))", ct).ConfigureAwait(false);
            try
            {
                await EnsureMigrationsTableAsync(conn, ct).ConfigureAwait(false);

                var isEmptyDatabase = await IsEmptyDatabaseAsync(conn, ct).ConfigureAwait(false);
                var migrationFiles = ListSqlFiles(Path.Combine(_dbFolderPath, "migrations"));

                if (isEmptyDatabase)
                {
                    var deployAllPath = Path.Combine(_dbFolderPath, "deploy_all.sql");
                    _logger.LogInformation("No application tables found - applying {File} as a one-shot baseline.", Path.GetFileName(deployAllPath));
                    await ApplyDeployAllAsync(conn, deployAllPath, ct).ConfigureAwait(false);

                    // deploy_all.sql is generated from the CURRENT schema/functions/seed, which
                    // already reflects everything migrations/ would otherwise apply - record every
                    // migration that exists today as already-applied so none is replayed on top of
                    // a table that was just created in its final shape.
                    foreach (var file in migrationFiles)
                    {
                        await RecordAppliedAsync(conn, Path.GetFileName(file), ct).ConfigureAwait(false);
                    }
                }
                else
                {
                    foreach (var file in migrationFiles)
                    {
                        var filename = Path.GetFileName(file);
                        if (await IsAppliedAsync(conn, filename, ct).ConfigureAwait(false))
                        {
                            continue;
                        }

                        _logger.LogInformation("Applying migration {Filename}", filename);
                        await ApplyMigrationAsync(conn, file, ct).ConfigureAwait(false);
                    }
                }

                foreach (var file in ListSqlFiles(Path.Combine(_dbFolderPath, "functions"), recursive: true))
                {
                    await ApplyIdempotentFileAsync(conn, file, ct).ConfigureAwait(false);
                }
                foreach (var file in ListSqlFiles(Path.Combine(_dbFolderPath, "seed")))
                {
                    await ApplyIdempotentFileAsync(conn, file, ct).ConfigureAwait(false);
                }

                await LogPostDeploySummaryAsync(conn, ct).ConfigureAwait(false);
            }
            finally
            {
                await ExecuteAsync(conn, $"SELECT pg_advisory_unlock(hashtext('{AdvisoryLockKey}'))", ct).ConfigureAwait(false);
            }
        }

        private static async Task<bool> IsEmptyDatabaseAsync(NpgsqlConnection conn, CancellationToken ct)
        {
            // Npgsql has no built-in object mapping for the regclass wire type, so cast to text.
            await using var cmd = new NpgsqlCommand("SELECT to_regclass('public.change_request')::text", conn);
            var result = await cmd.ExecuteScalarAsync(ct).ConfigureAwait(false);
            return result is null or DBNull;
        }

        private static Task EnsureMigrationsTableAsync(NpgsqlConnection conn, CancellationToken ct) =>
            ExecuteAsync(conn, """
                CREATE TABLE IF NOT EXISTS schema_migrations (
                    filename TEXT PRIMARY KEY,
                    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
                );
                """, ct);

        private static async Task<bool> IsAppliedAsync(NpgsqlConnection conn, string filename, CancellationToken ct)
        {
            await using var cmd = new NpgsqlCommand("SELECT 1 FROM schema_migrations WHERE filename = @filename", conn);
            cmd.Parameters.AddWithValue("filename", filename);
            var result = await cmd.ExecuteScalarAsync(ct).ConfigureAwait(false);
            return result is not null;
        }

        private static async Task RecordAppliedAsync(NpgsqlConnection conn, string filename, CancellationToken ct)
        {
            await using var cmd = new NpgsqlCommand(
                "INSERT INTO schema_migrations (filename) VALUES (@filename) ON CONFLICT (filename) DO NOTHING", conn);
            cmd.Parameters.AddWithValue("filename", filename);
            await cmd.ExecuteNonQueryAsync(ct).ConfigureAwait(false);
        }

        /// <summary>
        /// deploy_all.sql carries its own BEGIN/COMMIT (see generate_deploy_all.sh) since it also
        /// runs stand-alone via `psql -f` - executed directly rather than wrapped in a second,
        /// ADO.NET-managed transaction.
        /// </summary>
        private async Task ApplyDeployAllAsync(NpgsqlConnection conn, string path, CancellationToken ct)
        {
            var sql = await File.ReadAllTextAsync(path, ct).ConfigureAwait(false);
            try
            {
                await using var cmd = new NpgsqlCommand(sql, conn) { CommandTimeout = 300 };
                await cmd.ExecuteNonQueryAsync(ct).ConfigureAwait(false);
            }
            catch (PostgresException ex)
            {
                throw new InvalidOperationException($"Baseline deploy_all.sql failed: {ex.MessageText}", ex);
            }
        }

        /// <summary>
        /// A tracked, forward-only migration file: its own statements and the
        /// <c>schema_migrations</c> bookkeeping row commit together, so a crash between the two
        /// can never leave a migration applied-but-unrecorded (which would replay it) or
        /// recorded-but-unapplied (which would silently skip it).
        /// </summary>
        private async Task ApplyMigrationAsync(NpgsqlConnection conn, string path, CancellationToken ct)
        {
            var filename = Path.GetFileName(path);
            var sql = await File.ReadAllTextAsync(path, ct).ConfigureAwait(false);
            await using var tx = await conn.BeginTransactionAsync(ct).ConfigureAwait(false);
            try
            {
                await using (var cmd = new NpgsqlCommand(sql, conn, tx) { CommandTimeout = 120 })
                {
                    await cmd.ExecuteNonQueryAsync(ct).ConfigureAwait(false);
                }
                await using (var recordCmd = new NpgsqlCommand(
                    "INSERT INTO schema_migrations (filename) VALUES (@filename) ON CONFLICT (filename) DO NOTHING", conn, tx))
                {
                    recordCmd.Parameters.AddWithValue("filename", filename);
                    await recordCmd.ExecuteNonQueryAsync(ct).ConfigureAwait(false);
                }
                await tx.CommitAsync(ct).ConfigureAwait(false);
            }
            catch (PostgresException ex)
            {
                await tx.RollbackAsync(CancellationToken.None).ConfigureAwait(false);
                // US-12.1 AC3: halt and report exactly which file failed - never continue to the
                // next file, and never let the host start against a half-migrated schema (the
                // exception propagates out of RunAsync, which Program.cs does not catch).
                throw new InvalidOperationException($"Migration failed applying '{filename}': {ex.MessageText}", ex);
            }
        }

        private static readonly Regex FunctionNamePattern =
            new(@"CREATE\s+OR\s+REPLACE\s+FUNCTION\s+(\w+)\s*\(", RegexOptions.IgnoreCase | RegexOptions.Compiled);

        /// <summary>
        /// Functions and seed files: always re-applied, never tracked - safe because both are
        /// idempotent by construction. The one exception is a function whose RETURNS shape
        /// changed (Postgres's 42P13 "cannot change return type of existing function") - CREATE OR
        /// REPLACE can't do that in place, so this drops and recreates automatically instead of
        /// needing a one-off numbered migration for every such change (func_getChangeRequestsForUser
        /// hit exactly this when DEF-022 added two output columns).
        /// </summary>
        private async Task ApplyIdempotentFileAsync(NpgsqlConnection conn, string path, CancellationToken ct)
        {
            var sql = await File.ReadAllTextAsync(path, ct).ConfigureAwait(false);
            try
            {
                await ExecuteInOwnTransactionAsync(conn, sql, ct).ConfigureAwait(false);
            }
            catch (PostgresException ex) when (ex.SqlState == "42P13" && TryExtractFunctionName(sql, out var functionName))
            {
                _logger.LogInformation("{Function} changed its return shape - dropping and recreating.", functionName);
                await ExecuteAsync(conn, $"DROP FUNCTION IF EXISTS {functionName}", ct).ConfigureAwait(false);
                try
                {
                    await ExecuteInOwnTransactionAsync(conn, sql, ct).ConfigureAwait(false);
                }
                catch (PostgresException retryEx)
                {
                    throw new InvalidOperationException(
                        $"Failed applying '{Path.GetFileName(path)}' even after DROP FUNCTION {functionName}: {retryEx.MessageText}", retryEx);
                }
            }
            catch (PostgresException ex)
            {
                throw new InvalidOperationException($"Failed applying '{Path.GetFileName(path)}': {ex.MessageText}", ex);
            }
        }

        private static bool TryExtractFunctionName(string sql, out string functionName)
        {
            var match = FunctionNamePattern.Match(sql);
            functionName = match.Success ? match.Groups[1].Value : string.Empty;
            return match.Success;
        }

        private static async Task ExecuteInOwnTransactionAsync(NpgsqlConnection conn, string sql, CancellationToken ct)
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

        private static IReadOnlyList<string> ListSqlFiles(string folder, bool recursive = false)
        {
            if (!Directory.Exists(folder))
            {
                return [];
            }
            var files = Directory.GetFiles(folder, "*.sql", recursive ? SearchOption.AllDirectories : SearchOption.TopDirectoryOnly);
            Array.Sort(files, StringComparer.Ordinal);
            return files;
        }

        private static async Task ExecuteAsync(NpgsqlConnection conn, string sql, CancellationToken ct)
        {
            await using var cmd = new NpgsqlCommand(sql, conn);
            await cmd.ExecuteNonQueryAsync(ct).ConfigureAwait(false);
        }

        /// <summary>
        /// US-12.1 AC4's "documented post-deploy check" - logged on every startup (via the same
        /// ILogger pipeline Application Insights already hooks into, see Program.cs) rather than
        /// left as a query a person has to remember to run by hand.
        /// </summary>
        private async Task LogPostDeploySummaryAsync(NpgsqlConnection conn, CancellationToken ct)
        {
            await using var cmd = new NpgsqlCommand(
                "SELECT (SELECT count(*) FROM pg_proc WHERE proname LIKE 'func\\_%'), " +
                "(SELECT count(*) FROM risk_category), (SELECT count(*) FROM app_user)", conn);
            await using var reader = await cmd.ExecuteReaderAsync(ct).ConfigureAwait(false);
            if (await reader.ReadAsync(ct).ConfigureAwait(false))
            {
                _logger.LogInformation(
                    "Post-deploy check: {FunctionCount} func_ routines, {RiskCategoryCount} risk categories, {UserCount} seeded users",
                    reader.GetInt64(0), reader.GetInt64(1), reader.GetInt64(2));
            }
        }
    }
}
