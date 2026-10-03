namespace Humaid.RiskGovernance.AdminUI.Web.Controllers.Core
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core;
    using Humaid.RiskGovernance.AdminUI.Web.Auth;
    using Microsoft.AspNetCore.Mvc;
    using Npgsql;

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
            // DEF-005/DEF-018: a rejected value that only the database validates (a CHECK
            // constraint, or a domain RAISE EXCEPTION such as func_editNarrativeSection's "reason
            // is required") was falling into the generic 500 below, and where a controller did
            // catch it and echo ex.Message back, that message carried Npgsql's raw "SQLSTATE: "
            // prefix (e.g. "P0001: A reason is required..."). Map both cases to a clean 400 here,
            // once, instead of in every controller.
            //
            // Only RaiseException's MessageText is safe to return as-is - it's a string this
            // codebase's own PL/pgSQL wrote (e.g. "A reason is required..."). CheckViolation and
            // ForeignKeyViolation are Postgres's own generated text and can embed table/column/
            // constraint names (e.g. "violates check constraint \"committee_vote_check\""), so
            // those get a generic message instead - caught in AI review on this same PR.
            catch (PostgresException ex) when (ex.SqlState is PostgresErrorCodes.CheckViolation
                or PostgresErrorCodes.RaiseException or PostgresErrorCodes.ForeignKeyViolation
                or PostgresErrorCodes.InvalidTextRepresentation)
            {
                Logger.LogWarning(ex, "{ErrorMessage}", errorMessage);
                var message = ex.SqlState switch
                {
                    PostgresErrorCodes.RaiseException => ex.MessageText,
                    PostgresErrorCodes.ForeignKeyViolation => "One or more referenced records could not be found.",
                    _ => "One or more values are not in the expected format.",
                };
                return StatusCode(StatusCodes.Status400BadRequest, OperationResult<T>.BadRequest(message));
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
