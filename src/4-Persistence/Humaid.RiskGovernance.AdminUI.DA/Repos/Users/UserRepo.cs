namespace Humaid.RiskGovernance.AdminUI.DA.Repos.Users
{
    using Dapper;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Users;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Users;

    public class UserRepo : IUserRepo
    {
        private readonly DapperConnectionFactory _connectionFactory;

        public UserRepo(DapperConnectionFactory connectionFactory)
        {
            _connectionFactory = connectionFactory;
        }

        public async Task<IReadOnlyList<AppUser>> GetAllAsync()
        {
            await using var conn = await _connectionFactory.OpenAsync();
            var rows = await conn.QueryAsync<AppUser>("SELECT * FROM func_getAllUsers()");
            return rows.AsList();
        }

        public async Task<AppUser?> GetByAuth0SubjectAsync(string auth0Subject)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            return await conn.QuerySingleOrDefaultAsync<AppUser>(
                "SELECT * FROM func_getUserByAuth0Subject(@auth0Subject)", new { auth0Subject });
        }

        public async Task<AppUser?> GetByIdAsync(Guid id)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            return await conn.QuerySingleOrDefaultAsync<AppUser>(
                "SELECT * FROM func_getUserById(@id)", new { id });
        }
    }
}
