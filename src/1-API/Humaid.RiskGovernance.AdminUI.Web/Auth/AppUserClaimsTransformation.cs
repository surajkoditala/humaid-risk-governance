namespace Humaid.RiskGovernance.AdminUI.Web.Auth
{
    using System.Security.Claims;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.Users;
    using Microsoft.AspNetCore.Authentication;

    /// <summary>
    /// Epic 11 - turns "this request carries a valid Auth0 access token" into "this request is user X
    /// holding role Y". Runs after authentication on every request: it looks the caller's Auth0
    /// subject up in <c>app_user</c> and adds that row's id and role as claims.
    /// <para>
    /// The database row is the only source of the role. Any role claim already on the incoming
    /// identity (from a token, a proxy, anything) is discarded first, so a role can be granted or
    /// revoked only by changing <c>app_user</c> - and does take effect on the very next request.
    /// A caller with no active <c>app_user</c> row stays authenticated but gets no role, so every
    /// role-protected endpoint refuses them with 403.
    /// </para>
    /// </summary>
    public class AppUserClaimsTransformation : IClaimsTransformation
    {
        private readonly IUserService _userService;
        private readonly ILogger<AppUserClaimsTransformation> _logger;

        public AppUserClaimsTransformation(IUserService userService, ILogger<AppUserClaimsTransformation> logger)
        {
            _userService = userService;
            _logger = logger;
        }

        public async Task<ClaimsPrincipal> TransformAsync(ClaimsPrincipal principal)
        {
            // Can be invoked more than once per request; the added claims make it a no-op afterwards.
            if (principal.Identity?.IsAuthenticated != true || principal.HasClaim(c => c.Type == AppClaimTypes.UserId))
                return principal;

            var user = await ResolveUserAsync(principal);

            var clone = new ClaimsPrincipal();
            foreach (var identity in principal.Identities)
            {
                var copy = identity.Clone();
                foreach (var roleClaim in copy.FindAll(copy.RoleClaimType).ToList())
                    copy.RemoveClaim(roleClaim);
                clone.AddIdentity(copy);
            }

            if (user is null)
            {
                _logger.LogWarning(
                    "Authenticated caller {Subject} has no active app_user row; no role granted.",
                    principal.FindFirst(ClaimTypes.NameIdentifier)?.Value ?? "(no subject)");
                return clone;
            }

            var appIdentity = new ClaimsIdentity();
            appIdentity.AddClaim(new Claim(AppClaimTypes.UserId, user.Id.ToString()));
            appIdentity.AddClaim(new Claim(ClaimTypes.Role, user.Role));
            appIdentity.AddClaim(new Claim(ClaimTypes.Name, user.DisplayName));
            clone.AddIdentity(appIdentity);
            return clone;
        }

        private async Task<Infrastructure.Models.Users.AppUser?> ResolveUserAsync(ClaimsPrincipal principal)
        {
            // Local development only: DevBypassAuthHandler names the seeded user to act as.
            var devUserId = principal.FindFirst(AppClaimTypes.DevUserId)?.Value;
            if (devUserId is not null)
                return Guid.TryParse(devUserId, out var id) ? await _userService.GetByIdAsync(id) : null;

            var subject = principal.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            return string.IsNullOrWhiteSpace(subject) ? null : await _userService.GetByAuth0SubjectAsync(subject);
        }
    }
}
