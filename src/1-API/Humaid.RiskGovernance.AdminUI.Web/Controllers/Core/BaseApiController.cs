namespace Humaid.RiskGovernance.AdminUI.Web.Controllers.Core
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core;
    using Microsoft.AspNetCore.Mvc;

    /// <summary>
    /// Abstract base controller providing standardised action-result wrappers for every admin UI
    /// controller. Inherit from this instead of <see cref="ControllerBase"/> directly, and call
    /// <see cref="ExecuteAsync{T}"/> inside every action so exception handling, logging, and HTTP
    /// status mapping stay consistent.
    /// </summary>
    [ApiController]
    public abstract class BaseApiController : ControllerBase
    {
        protected readonly ILogger Logger;

        protected BaseApiController(ILogger logger)
        {
            Logger = logger ?? throw new ArgumentNullException(nameof(logger));
        }

        protected async Task<IActionResult> ExecuteAsync<T>(
            Func<Task<OperationResult<T>>> serviceCall,
            string errorMessage = "An unexpected error occurred.")
        {
            try
            {
                var result = await serviceCall().ConfigureAwait(false);

                if (result.IsSuccessful)
                    return Ok(result);

                var statusCode = result switch
                {
                    { IsBadRequest: true } => StatusCodes.Status400BadRequest,
                    { IsNotFound: true } => StatusCodes.Status404NotFound,
                    { IsConflict: true } => StatusCodes.Status409Conflict,
                    _ => StatusCodes.Status500InternalServerError,
                };

                return StatusCode(statusCode, result);
            }
            catch (Exception ex)
            {
                Logger.LogError(ex, "{ErrorMessage}", errorMessage);
                return StatusCode(
                    StatusCodes.Status500InternalServerError,
                    OperationResult<T>.Failure(errorMessage));
            }
        }
    }
}
