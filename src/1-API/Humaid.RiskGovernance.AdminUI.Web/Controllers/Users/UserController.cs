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

        /// <summary>Admin user-management screen: list/add/edit-roles/deactivate app_user rows,
        /// every change audited (func_createUser/func_setUserRoles/func_setUserActive/
        /// func_setUserAuth0Subject) the same way workflow_rule/scoring_config changes are.</summary>
        [HttpGet("Admin")]
        [Authorize(Roles = AppRoles.Admin)]
        public Task<IActionResult> GetAllForAdmin() =>
            ExecuteAsync(async () =>
            {
                var users = await _userService.GetAllForAdminAsync();
                return OperationResult<IReadOnlyList<AdminUserSummary>>.Success(users);
            }, "Failed to fetch users.");

        [HttpPost("Admin")]
        [Authorize(Roles = AppRoles.Admin)]
        public Task<IActionResult> CreateUser([FromBody] CreateUserInput input) =>
            ExecuteAsync(async () =>
            {
                if (RequireSelf<Guid>(input.ActorUserId) is { } forbidden) return forbidden;

                try
                {
                    var id = await _userService.CreateUserAsync(input);
                    return OperationResult<Guid>.Success(id);
                }
                catch (ValidationException ex)
                {
                    return OperationResult<Guid>.BadRequest(ex.Message);
                }
            }, "Failed to create user.");

        [HttpPost("Admin/{userId:guid}/Roles")]
        [Authorize(Roles = AppRoles.Admin)]
        public Task<IActionResult> SetUserRoles(Guid userId, [FromBody] SetUserRolesInput input) =>
            ExecuteAsync(async () =>
            {
                if (RequireSelf<object>(input.ActorUserId) is { } forbidden) return forbidden;

                input.UserId = userId;
                try
                {
                    await _userService.SetUserRolesAsync(input);
                    return OperationResult<object>.Success(new { });
                }
                catch (ValidationException ex)
                {
                    return OperationResult<object>.BadRequest(ex.Message);
                }
            }, "Failed to change user roles.");

        [HttpPost("Admin/{userId:guid}/Active")]
        [Authorize(Roles = AppRoles.Admin)]
        public Task<IActionResult> SetUserActive(Guid userId, [FromBody] SetUserActiveInput input) =>
            ExecuteAsync(async () =>
            {
                if (RequireSelf<object>(input.ActorUserId) is { } forbidden) return forbidden;

                input.UserId = userId;
                try
                {
                    await _userService.SetUserActiveAsync(input);
                    return OperationResult<object>.Success(new { });
                }
                catch (ValidationException ex)
                {
                    return OperationResult<object>.BadRequest(ex.Message);
                }
            }, "Failed to change user active status.");

        /// <summary>Links a real login to a user row - the UI form for what auth0-setup.md's step 4
        /// previously required a raw SQL UPDATE for.</summary>
        [HttpPost("Admin/{userId:guid}/Auth0Subject")]
        [Authorize(Roles = AppRoles.Admin)]
        public Task<IActionResult> SetUserAuth0Subject(Guid userId, [FromBody] SetUserAuth0SubjectInput input) =>
            ExecuteAsync(async () =>
            {
                if (RequireSelf<object>(input.ActorUserId) is { } forbidden) return forbidden;

                input.UserId = userId;
                try
                {
                    await _userService.SetUserAuth0SubjectAsync(input);
                    return OperationResult<object>.Success(new { });
                }
                catch (ValidationException ex)
                {
                    return OperationResult<object>.BadRequest(ex.Message);
                }
            }, "Failed to link Auth0 subject.");
    }
}
