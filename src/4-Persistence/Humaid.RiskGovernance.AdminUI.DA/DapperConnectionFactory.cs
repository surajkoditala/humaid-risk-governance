namespace Humaid.RiskGovernance.AdminUI.DA
{
    using Azure.Core;
    using Azure.Identity;
    using Microsoft.Extensions.Configuration;
    using Npgsql;

    /// <summary>
    /// Opens Npgsql connections for Dapper repos, reading the flat <c>AZURE_POSTGRESQL_CONNECTIONSTRING</c>
    /// configuration key (screaming-snake-case so it maps directly onto Container App env vars).
    /// <para>
    /// <c>AZURE_POSTGRESQL_ENDPOINT</c> is a fallback used only when
    /// <c>AZURE_POSTGRESQL_CONNECTIONSTRING</c> is blank — the same connection-string shape but
    /// without a password (Server/Database/Port/Ssl Mode/User Id), for Managed Identity (Entra ID)
    /// auth. A User Id present with no Password means Entra ID auth, and a
    /// <see cref="DefaultAzureCredential"/>-backed periodic token provider supplies (and refreshes)
    /// the password automatically.
    /// </para>
    /// </summary>
    public class DapperConnectionFactory
    {
        private static readonly string[] PostgresTokenScope = ["https://ossrdbms-aad.database.windows.net/.default"];

        private readonly NpgsqlDataSource _dataSource;

        public DapperConnectionFactory(IConfiguration configuration)
        {
            var connectionString = configuration["AZURE_POSTGRESQL_CONNECTIONSTRING"];
            if (string.IsNullOrWhiteSpace(connectionString))
            {
                connectionString = configuration["AZURE_POSTGRESQL_ENDPOINT"];
            }
            if (string.IsNullOrWhiteSpace(connectionString))
            {
                throw new InvalidOperationException(
                    "Neither AZURE_POSTGRESQL_CONNECTIONSTRING nor AZURE_POSTGRESQL_ENDPOINT is configured.");
            }

            var connStringBuilder = new NpgsqlConnectionStringBuilder(connectionString);
            var useEntraIdAuth = !string.IsNullOrEmpty(connStringBuilder.Username) && string.IsNullOrEmpty(connStringBuilder.Password);

            var dataSourceBuilder = new NpgsqlDataSourceBuilder(connStringBuilder.ConnectionString);
            if (useEntraIdAuth)
            {
                var credential = new DefaultAzureCredential();
                dataSourceBuilder.UsePeriodicPasswordProvider(
                    async (_, ct) =>
                    {
                        var token = await credential
                            .GetTokenAsync(new TokenRequestContext(PostgresTokenScope), ct)
                            .ConfigureAwait(false);
                        return token.Token;
                    },
                    TimeSpan.FromMinutes(55),
                    TimeSpan.FromSeconds(30));
            }

            _dataSource = dataSourceBuilder.Build();
        }

        /// <summary>Opens a new, already-open Npgsql connection. Callers own disposal.</summary>
        public async Task<NpgsqlConnection> OpenAsync(CancellationToken cancellationToken = default) =>
            await _dataSource.OpenConnectionAsync(cancellationToken).ConfigureAwait(false);
    }
}
