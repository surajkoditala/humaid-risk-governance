namespace Humaid.RiskGovernance.AdminUI.Web.Controllers.Users
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Users;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Users;
    using Humaid.RiskGovernance.AdminUI.Web.Auth;
    using Humaid.RiskGovernance.AdminUI.Web.Controllers.Core;
    using Microsoft.AspNetCore.Authorization;
    using Microsoft.AspNetCore.Mvc;

    /// <summary>Epic 11. GetAll is the webapp's "acting as" switcher - open in local dev, Admin-only
    /// once real Auth0 login is wired in (AccessPolicies.UserDirectory). Me is what every screen
    /// should switch to reading from once a real Auth0 tenant replaces the dev bypass - see
    /// DevUserContext.jsx.</summary>
    [Authorize]
    [Route("api/[controller]")]
    public class UserController : BaseApiController
    {
        private readonly IUserService _userService;

        public UserController(IUserService userService, ILogger<UserController> logger)
            : base(logger)
        {
            _userService = userService;
        }

        [HttpGet]
        [Authorize(Policy = AccessPolicies.UserDirectory)]
        public Task<IActionResult> GetAll() =>
            ExecuteAsync(async () =>
            {
                var users = await _userService.GetAllAsync();
                return OperationResult<IReadOnlyList<AppUser>>.Success(users);
            }, "Failed to fetch users.");

        /// <summary>The caller's own identity and role, as resolved server-side from their credential
        /// (Auth0 token, or the dev "acting as" header) - never from anything the client asserts.</summary>
        [HttpGet("Me")]
        public Task<IActionResult> GetMe() =>
            ExecuteAsync(async () =>
            {
                var userId = User.GetAppUserId();
                var user = userId is null ? null : await _userService.GetByIdAsync(userId.Value);
                return user is null
                    ? OperationResult<AppUser>.Forbidden("No active user is associated with this account.")
                    : OperationResult<AppUser>.Success(user);
            }, "Failed to fetch the current user.");
    }
}
