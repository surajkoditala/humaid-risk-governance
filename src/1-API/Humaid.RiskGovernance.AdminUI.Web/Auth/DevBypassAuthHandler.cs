namespace Humaid.RiskGovernance.AdminUI.Web.Auth
{
    using System.Security.Claims;
    using System.Text.Encodings.Web;
    using Microsoft.AspNetCore.Authentication;
    using Microsoft.Extensions.Logging;
    using Microsoft.Extensions.Options;

    /// <summary>
    /// Development-only stand-in for Auth0 JWT validation. Registered in Program.cs ONLY when
    /// both <c>AUTH0_DOMAIN</c> is blank AND the environment is Development - the same condition
    /// the webapp's own RequireAuth.jsx already uses to decide whether to bypass Auth0 Universal
    /// Login. Without this, a frontend running in that bypass mode has no token to send and every
    /// [Authorize]-protected endpoint returns 401 regardless of what the UI does.
    /// <para>
    /// Authenticates every request as a generic "system-dev" identity - there is no real login
    /// here, so it carries no meaningful claims. Every write endpoint in this app already takes
    /// the acting user's id explicitly in the request body (see the NOTE in
    /// ChangeRequestController.cs) rather than reading it from the token, so this identity is
    /// only ever used to satisfy [Authorize] itself, never to authorize a specific action.
    /// </para>
    /// </summary>
    public class DevBypassAuthHandler : AuthenticationHandler<AuthenticationSchemeOptions>
    {
        public const string SchemeName = "DevBypass";

        public DevBypassAuthHandler(IOptionsMonitor<AuthenticationSchemeOptions> options, ILoggerFactory logger, UrlEncoder encoder)
            : base(options, logger, encoder)
        {
        }

        protected override Task<AuthenticateResult> HandleAuthenticateAsync()
        {
            var identity = new ClaimsIdentity([new Claim(ClaimTypes.NameIdentifier, "system-dev")], SchemeName);
            var ticket = new AuthenticationTicket(new ClaimsPrincipal(identity), SchemeName);
            return Task.FromResult(AuthenticateResult.Success(ticket));
        }
    }
}
