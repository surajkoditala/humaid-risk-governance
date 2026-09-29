namespace Humaid.RiskGovernance.AdminUI.Services.Users
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Users;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Users;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core;
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

        public Task<IReadOnlyList<AdminUserSummary>> GetAllForAdminAsync() => _userRepo.GetAllForAdminAsync();

        public Task<Guid> CreateUserAsync(CreateUserInput input)
        {
            if (string.IsNullOrWhiteSpace(input.Reason))
            {
                throw new ValidationException("A reason is required to create a user.");
            }
            if (input.Roles is null || input.Roles.Length == 0)
            {
                throw new ValidationException("A user must be created with at least one role.");
            }
            return _userRepo.CreateAsync(input);
        }

        public Task SetUserRolesAsync(SetUserRolesInput input)
        {
            if (string.IsNullOrWhiteSpace(input.Reason))
            {
                throw new ValidationException("A reason is required to change a user's roles.");
            }
            if (input.Roles is null || input.Roles.Length == 0)
            {
                throw new ValidationException("A user must hold at least one role.");
            }
            return _userRepo.SetRolesAsync(input);
        }

        public Task SetUserActiveAsync(SetUserActiveInput input)
        {
            if (string.IsNullOrWhiteSpace(input.Reason))
            {
                throw new ValidationException("A reason is required to deactivate or reactivate a user.");
            }
            return _userRepo.SetActiveAsync(input);
        }

        public Task SetUserAuth0SubjectAsync(SetUserAuth0SubjectInput input)
        {
            if (string.IsNullOrWhiteSpace(input.Reason))
            {
                throw new ValidationException("A reason is required to link an Auth0 login.");
            }
            if (string.IsNullOrWhiteSpace(input.Auth0Subject))
            {
                throw new ValidationException("An Auth0 subject is required.");
            }
            return _userRepo.SetAuth0SubjectAsync(input);
        }
    }
}
