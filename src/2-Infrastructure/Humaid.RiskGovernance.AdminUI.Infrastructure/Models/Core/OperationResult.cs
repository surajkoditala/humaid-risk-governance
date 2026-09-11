namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core
{
    /// <summary>
    /// Standard envelope every service method returns, mapped to an HTTP response by
    /// <c>BaseApiController.ExecuteAsync</c> — success/data, or one of the failure shapes below.
    /// </summary>
    public class OperationResult<T>
    {
        public bool IsSuccessful { get; private init; }

        public bool IsBadRequest { get; private init; }

        public bool IsNotFound { get; private init; }

        public bool IsConflict { get; private init; }

        public T? Data { get; private init; }

        public string? Message { get; private init; }

        public static OperationResult<T> Success(T data, string? message = null) =>
            new() { IsSuccessful = true, Data = data, Message = message };

        public static OperationResult<T> Failure(string message) =>
            new() { IsSuccessful = false, Message = message };

        public static OperationResult<T> BadRequest(string message) =>
            new() { IsSuccessful = false, IsBadRequest = true, Message = message };

        public static OperationResult<T> NotFound(string message) =>
            new() { IsSuccessful = false, IsNotFound = true, Message = message };

        public static OperationResult<T> Conflict(string message) =>
            new() { IsSuccessful = false, IsConflict = true, Message = message };
    }
}
