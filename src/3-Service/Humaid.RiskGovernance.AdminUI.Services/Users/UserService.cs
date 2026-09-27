namespace Humaid.RiskGovernance.AdminUI.Services.Users
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Users;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Users;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Users;

    public class UserService : IUserService
    {
        private readonly IUserRepo _userRepo;

        public UserService(IUserRepo userRepo)
        {
            _userRepo = userRepo;
        }

        public Task<IReadOnlyList<AppUser>> GetAllAsync() => _userRepo.GetAllAsync();

        public Task<AppUser?> GetByAuth0SubjectAsync(string auth0Subject) => _userRepo.GetByAuth0SubjectAsync(auth0Subject);

        public Task<AppUser?> GetByIdAsync(Guid id) => _userRepo.GetByIdAsync(id);
    }
}
