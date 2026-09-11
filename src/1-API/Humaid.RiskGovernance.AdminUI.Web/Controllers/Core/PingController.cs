namespace Humaid.RiskGovernance.AdminUI.Web.Controllers.Core
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core;
    using Microsoft.AspNetCore.Mvc;

    /// <summary>
    /// Reference vertical slice proving the Controller → BaseApiController → OperationResult wiring
    /// works end to end. No <see cref="Microsoft.AspNetCore.Authorization.AuthorizeAttribute"/> —
    /// safe for the webapp (or curl) to call before Auth0 is even configured. Delete once a real
    /// screen replaces it as the first wired-up vertical slice.
    /// </summary>
    [ApiController]
    [Route("api/[controller]")]
    public class PingController : BaseApiController
    {
        public PingController(ILogger<PingController> logger)
            : base(logger)
        {
        }

        [HttpGet]
        public Task<IActionResult> Get() =>
            ExecuteAsync(() => Task.FromResult(OperationResult<string>.Success("pong")));
    }
}
