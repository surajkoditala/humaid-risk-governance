namespace Humaid.RiskGovernance.AdminUI.Web.Auth
{
    using System.Security.Claims;

    /// <summary>
    /// The claims this app adds to a validated caller (Epic 11). They are added server-side from the
    /// caller's <c>app_user</c> row by <see cref="AppUserClaimsTransformation"/>, never read from the
    /// access token or the request, so neither a token claim nor a payload field can grant a role or
    /// pick the acting user.
    /// </summary>
    public static class AppClaimTypes
    {
        /// <summary>The caller's <c>app_user.id</c>.</summary>
        public const string UserId = "app_user_id";

        /// <summary>Set only by <see cref="DevBypassAuthHandler"/>: the <c>app_user.id</c> the local
        /// "acting as" switcher asked to run as. Resolved to a real user by the claims transformation.</summary>
        public const string DevUserId = "dev_user_id";
    }

    public static class ClaimsPrincipalExtensions
    {
        /// <summary>The caller's <c>app_user.id</c>, or null when the caller is authenticated but is
        /// not a provisioned, active user (no <c>app_user</c> row for their Auth0 subject).</summary>
        public static Guid? GetAppUserId(this ClaimsPrincipal principal) =>
            Guid.TryParse(principal.FindFirst(AppClaimTypes.UserId)?.Value, out var id) ? id : null;

        /// <summary>The caller's role (an <c>AppRoles</c> value), or null when not provisioned.</summary>
        public static string? GetAppRole(this ClaimsPrincipal principal) =>
            principal.FindFirst(ClaimTypes.Role)?.Value;
    }
}
