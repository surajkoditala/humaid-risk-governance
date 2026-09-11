namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Users
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Users;

    /// <summary>Dev-only convenience - see IUserRepo.cs and DevBypassAuthHandler.cs.</summary>
    public interface IUserService
    {
        Task<IReadOnlyList<AppUser>> GetAllAsync();
    }
}
