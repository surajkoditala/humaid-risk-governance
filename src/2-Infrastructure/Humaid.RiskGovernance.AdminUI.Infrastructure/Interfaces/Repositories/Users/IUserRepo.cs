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
    }
}
