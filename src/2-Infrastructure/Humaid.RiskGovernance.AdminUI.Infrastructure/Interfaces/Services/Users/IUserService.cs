namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Users
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Users;

    /// <summary>Epic 11 - resolves who is calling (by Auth0 subject, or by id in local dev) to the
    /// app_user row that owns their role. GetAllAsync is the dev-only "acting as" listing.</summary>
    public interface IUserService
    {
        Task<IReadOnlyList<AppUser>> GetAllAsync();

        Task<AppUser?> GetByAuth0SubjectAsync(string auth0Subject);

        Task<AppUser?> GetByIdAsync(Guid id);

        /// <summary>Admin user-management screen: every user, active or not.</summary>
        Task<IReadOnlyList<AdminUserSummary>> GetAllForAdminAsync();

        /// <summary>Reason and at-least-one-role are mandatory - enforced by func_createUser.</summary>
        Task<Guid> CreateUserAsync(CreateUserInput input);

        /// <summary>Replaces the user's entire role set - enforced by func_setUserRoles.</summary>
        Task SetUserRolesAsync(SetUserRolesInput input);

        Task SetUserActiveAsync(SetUserActiveInput input);

        Task SetUserAuth0SubjectAsync(SetUserAuth0SubjectInput input);

        /// <summary>Epic 11 follow-up: fallback for a caller whose Auth0 subject matches no row -
        /// claims an existing, not-yet-linked row by email instead. Null if no such row exists.</summary>
        Task<AppUser?> LinkAuth0ByEmailAsync(string email, string auth0Subject);
    }
}
