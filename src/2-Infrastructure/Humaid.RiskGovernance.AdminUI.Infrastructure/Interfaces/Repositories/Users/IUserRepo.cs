namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Users
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Users;

    public interface IUserRepo
    {
        Task<IReadOnlyList<AppUser>> GetAllAsync();

        /// <summary>DEF-002: role lookup used to validate a caller-supplied actor id actually
        /// holds the role an action requires. Null if the id doesn't resolve to an active user.</summary>
        Task<string?> GetRoleAsync(Guid userId);
    }
}
