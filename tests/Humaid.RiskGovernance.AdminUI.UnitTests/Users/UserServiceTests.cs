namespace Humaid.RiskGovernance.AdminUI.UnitTests.Users
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Repositories.Users;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Users;
    using Humaid.RiskGovernance.AdminUI.Services.Users;
    using Moq;
    using Xunit;

    /// <summary>Admin user-management screen: reason-mandatory and at-least-one-role validation,
    /// checked here too (like every other Admin-owned write - see WorkflowRuleServiceTests) so the
    /// API returns a clean 400 instead of a raw DB exception.</summary>
    public class UserServiceTests
    {
        private readonly Mock<IUserRepo> _userRepo = new();
        private readonly UserService _sut;

        public UserServiceTests()
        {
            _sut = new UserService(_userRepo.Object);
        }

        private static CreateUserInput ValidCreateInput() => new()
        {
            Email = "new.analyst@example.bank",
            DisplayName = "New Analyst",
            Roles = ["Analyst"],
            Reason = "Onboarding",
            ActorUserId = Guid.NewGuid(),
        };

        [Fact]
        public async Task CreateUserAsync_RejectsBlankReason()
        {
            var input = ValidCreateInput();
            input.Reason = "   ";

            await Assert.ThrowsAsync<ValidationException>(() => _sut.CreateUserAsync(input));
            _userRepo.Verify(r => r.CreateAsync(It.IsAny<CreateUserInput>()), Times.Never);
        }

        [Fact]
        public async Task CreateUserAsync_RejectsNoRoles()
        {
            var input = ValidCreateInput();
            input.Roles = [];

            await Assert.ThrowsAsync<ValidationException>(() => _sut.CreateUserAsync(input));
            _userRepo.Verify(r => r.CreateAsync(It.IsAny<CreateUserInput>()), Times.Never);
        }

        [Fact]
        public async Task CreateUserAsync_AllowsAValidRequest()
        {
            var id = Guid.NewGuid();
            _userRepo.Setup(r => r.CreateAsync(It.IsAny<CreateUserInput>())).ReturnsAsync(id);

            var result = await _sut.CreateUserAsync(ValidCreateInput());

            Assert.Equal(id, result);
        }

        [Fact]
        public async Task SetUserRolesAsync_RejectsNoRoles()
        {
            var input = new SetUserRolesInput { UserId = Guid.NewGuid(), Roles = [], Reason = "test", ActorUserId = Guid.NewGuid() };

            await Assert.ThrowsAsync<ValidationException>(() => _sut.SetUserRolesAsync(input));
            _userRepo.Verify(r => r.SetRolesAsync(It.IsAny<SetUserRolesInput>()), Times.Never);
        }

        [Fact]
        public async Task SetUserActiveAsync_RejectsBlankReason()
        {
            var input = new SetUserActiveInput { UserId = Guid.NewGuid(), IsActive = false, Reason = "", ActorUserId = Guid.NewGuid() };

            await Assert.ThrowsAsync<ValidationException>(() => _sut.SetUserActiveAsync(input));
            _userRepo.Verify(r => r.SetActiveAsync(It.IsAny<SetUserActiveInput>()), Times.Never);
        }

        [Fact]
        public async Task SetUserAuth0SubjectAsync_RejectsBlankSubject()
        {
            var input = new SetUserAuth0SubjectInput { UserId = Guid.NewGuid(), Auth0Subject = "  ", Reason = "linking real login", ActorUserId = Guid.NewGuid() };

            await Assert.ThrowsAsync<ValidationException>(() => _sut.SetUserAuth0SubjectAsync(input));
            _userRepo.Verify(r => r.SetAuth0SubjectAsync(It.IsAny<SetUserAuth0SubjectInput>()), Times.Never);
        }
    }
}
