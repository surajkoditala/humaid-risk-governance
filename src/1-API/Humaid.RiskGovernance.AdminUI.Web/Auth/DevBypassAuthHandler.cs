namespace Humaid.RiskGovernance.AdminUI.Web.Auth
{
    using System.Security.Claims;
    using System.Text.Encodings.Web;
    using Microsoft.AspNetCore.Authentication;
    using Microsoft.Extensions.Logging;
    using Microsoft.Extensions.Options;

    /// <summary>
    /// Local-development stand-in for Auth0 JWT validation, so the webapp's "acting as" switcher works
    /// without an Auth0 tenant. Program.cs registers it ONLY when <c>AUTH0_DOMAIN</c> is blank AND the
    /// environment is Development AND the process is not hosted in Azure Container Apps - anywhere else
    /// a missing Auth0 configuration stops the app at startup instead of opening it up.
    /// <para>
    /// There is no login here. A request that names a seeded user in the <c>X-Dev-User-Id</c> header
    /// is that user; the claims transformation resolves the id to an <c>app_user</c> row exactly as it
    /// resolves a real Auth0 subject, so the SAME role checks apply to a switched-in local user as to a
    /// real one. A request with no header is authenticated but has no role, so every role-protected
    /// endpoint answers 403 - "acting as" nobody grants nothing.
    /// </para>
    /// </summary>
    public class DevBypassAuthHandler : AuthenticationHandler<AuthenticationSchemeOptions>
    {
        public const string SchemeName = "DevBypass";

        /// <summary>Request header the webapp's dev-user switcher sets to the chosen <c>app_user.id</c>.</summary>
        public const string UserHeader = "X-Dev-User-Id";

        public DevBypassAuthHandler(IOptionsMonitor<AuthenticationSchemeOptions> options, ILoggerFactory logger, UrlEncoder encoder)
            : base(options, logger, encoder)
        {
        }

        protected override Task<AuthenticateResult> HandleAuthenticateAsync()
        {
            var claims = new List<Claim> { new(ClaimTypes.NameIdentifier, "system-dev") };

            if (Request.Headers.TryGetValue(UserHeader, out var header) && Guid.TryParse(header.ToString(), out var userId))
                claims.Add(new Claim(AppClaimTypes.DevUserId, userId.ToString()));

            var identity = new ClaimsIdentity(claims, SchemeName);
            var ticket = new AuthenticationTicket(new ClaimsPrincipal(identity), SchemeName);
            return Task.FromResult(AuthenticateResult.Success(ticket));
        }
    }
}
