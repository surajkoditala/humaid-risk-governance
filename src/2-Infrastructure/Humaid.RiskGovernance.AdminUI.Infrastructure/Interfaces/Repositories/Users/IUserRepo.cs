namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Users
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Users;

    public interface IUserRepo
    {
        Task<IReadOnlyList<AppUser>> GetAllAsync();
    }
}
