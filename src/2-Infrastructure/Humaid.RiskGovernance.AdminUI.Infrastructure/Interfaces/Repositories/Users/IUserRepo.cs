namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Users
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Users;

    public interface IUserRepo
    {
        Task<IReadOnlyList<AppUser>> GetAllAsync();

        /// <summary>Epic 11: the active user whose Auth0 'sub' claim this is, or null if none.</summary>
        Task<AppUser?> GetByAuth0SubjectAsync(string auth0Subject);

        /// <summary>Epic 11: the active user with this id, or null if none. Local-dev "acting as" only.</summary>
        Task<AppUser?> GetByIdAsync(Guid id);

        /// <summary>DEF-002: role lookup used to validate a caller-supplied actor id actually
        /// holds the role an action requires - false if the id doesn't resolve to an active user.
        /// A membership check, not "the" role, since a user can hold more than one
        /// (app_user_role, Epic 11 follow-up).</summary>
        Task<bool> HasRoleAsync(Guid userId, string role);

        /// <summary>Admin user-management screen: every user, active or not.</summary>
        Task<IReadOnlyList<AdminUserSummary>> GetAllForAdminAsync();

        Task<Guid> CreateAsync(CreateUserInput input);

        Task SetRolesAsync(SetUserRolesInput input);

        Task SetActiveAsync(SetUserActiveInput input);

        Task SetAuth0SubjectAsync(SetUserAuth0SubjectInput input);

        /// <summary>Epic 11 follow-up: fallback for a caller whose Auth0 subject matches no row -
        /// claims an existing, not-yet-linked (auth0_subject IS NULL) row by email instead. Null if
        /// no such row exists.</summary>
        Task<AppUser?> LinkAuth0ByEmailAsync(string email, string auth0Subject);
    }
}
