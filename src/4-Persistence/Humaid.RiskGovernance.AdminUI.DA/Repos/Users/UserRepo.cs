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

        public async Task<bool> HasRoleAsync(Guid userId, string role)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            return await conn.QuerySingleAsync<bool>(
                "SELECT func_userHasRole(@userId, @role)", new { userId, role });
        }

        public async Task<IReadOnlyList<AdminUserSummary>> GetAllForAdminAsync()
        {
            await using var conn = await _connectionFactory.OpenAsync();
            var rows = await conn.QueryAsync<AdminUserSummary>("SELECT * FROM func_getAllUsersForAdmin()");
            return rows.AsList();
        }

        public async Task<Guid> CreateAsync(CreateUserInput input)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            return await conn.QuerySingleAsync<Guid>(
                "SELECT func_createUser(@Email, @DisplayName, @Roles, @Reason, @ActorUserId)", input);
        }

        public async Task SetRolesAsync(SetUserRolesInput input)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            await conn.ExecuteAsync(
                "SELECT func_setUserRoles(@UserId, @Roles, @Reason, @ActorUserId)", input);
        }

        public async Task SetActiveAsync(SetUserActiveInput input)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            await conn.ExecuteAsync(
                "SELECT func_setUserActive(@UserId, @IsActive, @Reason, @ActorUserId)", input);
        }

        public async Task SetAuth0SubjectAsync(SetUserAuth0SubjectInput input)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            await conn.ExecuteAsync(
                "SELECT func_setUserAuth0Subject(@UserId, @Auth0Subject, @Reason, @ActorUserId)", input);
        }

        public async Task<AppUser?> LinkAuth0ByEmailAsync(string email, string auth0Subject)
        {
            await using var conn = await _connectionFactory.OpenAsync();
            return await conn.QuerySingleOrDefaultAsync<AppUser>(
                "SELECT * FROM func_linkUserAuth0ByEmail(@email, @auth0Subject)", new { email, auth0Subject });
        }
    }
}
