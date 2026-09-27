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
    }
}
