namespace Humaid.RiskGovernance.AdminUI.UnitTests.Auth
{
    using System.Security.Claims;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Users;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Users;
    using Humaid.RiskGovernance.AdminUI.Web.Auth;
    using Microsoft.Extensions.Logging.Abstractions;
    using Moq;
    using Xunit;

    /// <summary>
    /// Epic 11: the transformation is what turns "this token is valid" into "this caller is user X
    /// holding role Y" - the app_user row is the only source of the role, never a token claim, so
    /// these tests exercise that specifically (see DEF-002/DEF-010 in the QA execution report:
    /// nothing previously stopped a caller from asserting their own role or acting-as id).
    /// </summary>
    public class AppUserClaimsTransformationTests
    {
        private readonly Mock<IUserService> _userService = new();
        private readonly AppUserClaimsTransformation _sut;

        public AppUserClaimsTransformationTests()
        {
            _sut = new AppUserClaimsTransformation(_userService.Object, NullLogger<AppUserClaimsTransformation>.Instance);
        }

        private static ClaimsPrincipal Authenticated(params Claim[] claims) =>
            new(new ClaimsIdentity(claims, "TestScheme"));

        [Fact]
        public async Task ResolvesAuth0SubjectToAppUserIdAndRole()
        {
            var userId = Guid.NewGuid();
            _userService.Setup(s => s.GetByAuth0SubjectAsync("auth0|abc123"))
                .ReturnsAsync(new AppUser { Id = userId, Roles = [AppRoles.Analyst], DisplayName = "Amara Chen" });

            var principal = Authenticated(new Claim(ClaimTypes.NameIdentifier, "auth0|abc123"));
            var result = await _sut.TransformAsync(principal);

            Assert.Equal(userId, result.GetAppUserId());
            Assert.Equal([AppRoles.Analyst], result.GetAppRoles());
            Assert.True(result.IsInRole(AppRoles.Analyst));
        }

        [Fact]
        public async Task ResolvesEveryRoleGrantForAUserHoldingSeveral()
        {
            // Epic 11 follow-up: app_user_role, not a single app_user.role column - a caller can
            // hold more than one role, and every one of them must land as its own claim so
            // [Authorize(Roles = "X,Y")]'s built-in OR-matching sees all of them.
            var userId = Guid.NewGuid();
            _userService.Setup(s => s.GetByAuth0SubjectAsync("auth0|multi"))
                .ReturnsAsync(new AppUser
                {
                    Id = userId,
                    Roles = [AppRoles.ProductOwner, AppRoles.Analyst, AppRoles.CommitteeMember, AppRoles.Admin],
                    DisplayName = "Francis Daray",
                });

            var principal = Authenticated(new Claim(ClaimTypes.NameIdentifier, "auth0|multi"));
            var result = await _sut.TransformAsync(principal);

            Assert.Equal(userId, result.GetAppUserId());
            Assert.Equal(4, result.GetAppRoles().Count);
            foreach (var role in AppRoles.All)
                Assert.True(result.IsInRole(role));
        }

        [Fact]
        public async Task UnrecognizedAuth0SubjectStaysAuthenticatedWithNoRole()
        {
            _userService.Setup(s => s.GetByAuth0SubjectAsync(It.IsAny<string>())).ReturnsAsync((AppUser?)null);

            var principal = Authenticated(new Claim(ClaimTypes.NameIdentifier, "auth0|unknown"));
            var result = await _sut.TransformAsync(principal);

            Assert.True(result.Identity!.IsAuthenticated);
            Assert.Null(result.GetAppUserId());
            Assert.Empty(result.GetAppRoles());
            Assert.False(result.IsInRole(AppRoles.Admin));
        }

        [Fact]
        public async Task DevUserIdClaimResolvesByIdInsteadOfAuth0Subject()
        {
            var userId = Guid.NewGuid();
            _userService.Setup(s => s.GetByIdAsync(userId))
                .ReturnsAsync(new AppUser { Id = userId, Roles = [AppRoles.CommitteeMember], DisplayName = "Jordan Blake" });

            // DevBypassAuthHandler always sets NameIdentifier to "system-dev" - the dev user id claim
            // must take priority over it, or "acting as" would never resolve a role locally.
            var principal = Authenticated(
                new Claim(ClaimTypes.NameIdentifier, "system-dev"),
                new Claim(AppClaimTypes.DevUserId, userId.ToString()));

            var result = await _sut.TransformAsync(principal);

            Assert.Equal(userId, result.GetAppUserId());
            Assert.Equal([AppRoles.CommitteeMember], result.GetAppRoles());
            _userService.Verify(s => s.GetByAuth0SubjectAsync(It.IsAny<string>()), Times.Never);
        }

        [Fact]
        public async Task DiscardsAnyRoleClaimAlreadyOnTheIncomingIdentity()
        {
            // A role claim from anywhere other than app_user (a forged/replayed token, a
            // misconfigured upstream proxy) must never survive the transformation - the database
            // rows are the only source of truth for role.
            _userService.Setup(s => s.GetByAuth0SubjectAsync("auth0|abc123"))
                .ReturnsAsync(new AppUser { Id = Guid.NewGuid(), Roles = [AppRoles.Analyst], DisplayName = "Amara Chen" });

            var principal = Authenticated(
                new Claim(ClaimTypes.NameIdentifier, "auth0|abc123"),
                new Claim(ClaimTypes.Role, AppRoles.Admin));

            var result = await _sut.TransformAsync(principal);

            Assert.False(result.IsInRole(AppRoles.Admin));
            Assert.True(result.IsInRole(AppRoles.Analyst));
            Assert.Single(result.FindAll(ClaimTypes.Role));
        }

        [Fact]
        public async Task IsANoOpOnceAlreadyTransformed()
        {
            var principal = Authenticated(new Claim(AppClaimTypes.UserId, Guid.NewGuid().ToString()));

            var result = await _sut.TransformAsync(principal);

            Assert.Same(principal, result);
            _userService.Verify(s => s.GetByAuth0SubjectAsync(It.IsAny<string>()), Times.Never);
            _userService.Verify(s => s.GetByIdAsync(It.IsAny<Guid>()), Times.Never);
        }
    }
}
