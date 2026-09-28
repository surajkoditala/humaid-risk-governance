namespace Humaid.RiskGovernance.AdminUI.Web.Controllers.Core
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core;
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
            catch (PostgresException ex) when (ex.SqlState is PostgresErrorCodes.CheckViolation
                or PostgresErrorCodes.RaiseException or PostgresErrorCodes.ForeignKeyViolation
                or PostgresErrorCodes.InvalidTextRepresentation)
            {
                Logger.LogWarning(ex, "{ErrorMessage}", errorMessage);
                return StatusCode(
                    StatusCodes.Status400BadRequest,
                    OperationResult<T>.BadRequest(ex.SqlState == PostgresErrorCodes.InvalidTextRepresentation
                        ? "One or more values are not in the expected format."
                        : ex.MessageText));
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
