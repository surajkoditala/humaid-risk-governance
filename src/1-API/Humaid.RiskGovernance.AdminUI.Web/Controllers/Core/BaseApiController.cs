namespace Humaid.RiskGovernance.AdminUI.Web.Controllers.Core
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core;
    using Humaid.RiskGovernance.AdminUI.Web.Auth;
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
                    { IsForbidden: true } => StatusCodes.Status403Forbidden,
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

        /// <summary>Epic 11 (closes DEF-002): every write action still takes the acting user's id as
        /// an explicit request field (see the NOTE on ChangeRequestController), rather than this
        /// codebase resolving it from the token on every call site. This is what makes that field
        /// trustworthy again - call it first in the action, with the id from the request body/form,
        /// and return the result immediately if it's non-null. A caller can only ever act as the
        /// identity <see cref="AppUserClaimsTransformation"/> resolved from their own credential, so
        /// impersonation-by-request-field (a Product Owner voting by putting a committee member's id
        /// in the body) is rejected here, before the service layer ever runs.</summary>
        protected OperationResult<T>? RequireSelf<T>(Guid claimedUserId)
        {
            var callerId = User.GetAppUserId();
            if (callerId is null)
                return OperationResult<T>.Forbidden("No active user is associated with this account.");
            if (claimedUserId != callerId)
                return OperationResult<T>.Forbidden("The acting user must be the authenticated caller.");
            return null;
        }
    }
}
