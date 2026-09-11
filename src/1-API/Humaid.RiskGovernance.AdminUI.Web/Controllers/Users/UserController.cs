namespace Humaid.RiskGovernance.AdminUI.Web.Controllers.Users
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Users;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Users;
    using Humaid.RiskGovernance.AdminUI.Web.Controllers.Core;
    using Microsoft.AspNetCore.Authorization;
    using Microsoft.AspNetCore.Mvc;

    /// <summary>Dev-only convenience for the webapp's "acting as" switcher - see
    /// IUserRepo.cs and DevBypassAuthHandler.cs. Not meant to survive real auth being wired in.</summary>
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
        public Task<IActionResult> GetAll() =>
            ExecuteAsync(async () =>
            {
                var users = await _userService.GetAllAsync();
                return OperationResult<IReadOnlyList<AppUser>>.Success(users);
            }, "Failed to fetch users.");
    }
}
