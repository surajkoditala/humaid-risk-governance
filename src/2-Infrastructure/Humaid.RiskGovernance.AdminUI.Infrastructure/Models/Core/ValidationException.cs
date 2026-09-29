namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core
{
    /// <summary>
    /// AI review on PR #60: a Service method throws this - never a plain
    /// <see cref="InvalidOperationException"/> - to signal a business-rule failure it wants
    /// echoed back to the caller as a clean 400 (e.g. "A reason is required..."). A controller
    /// catches only this type; an <see cref="InvalidOperationException"/> from a misconfigured AI
    /// client, blob storage, or any other dependency is left uncaught and falls through to
    /// BaseApiController.ExecuteAsync's generic 500 + log path instead of being misreported as
    /// the caller's fault.
    /// </summary>
    public class ValidationException : Exception
    {
        public ValidationException(string message) : base(message) { }
    }
}
