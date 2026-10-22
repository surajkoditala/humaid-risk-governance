namespace Humaid.RiskGovernance.AdminUI.Web.Auth
{
    using System.Text.Json.Serialization;

    /// <summary>
    /// The Auth0 settings the SPA needs to start a login, served at <c>/config.json</c> so they come
    /// from this container's own environment (runtime) instead of being inlined into the JavaScript
    /// bundle when the image is built. One image then works for any tenant/environment, and the
    /// backend's AUTH0_DOMAIN / AUTH0_AUDIENCE stay the single source of truth for the audience and
    /// domain the SPA requests tokens for.
    ///
    /// All three values are public by design (they appear in every browser's login redirect), so the
    /// endpoint is anonymous. Nothing secret may ever be added to this record.
    /// </summary>
    public record ClientAuthConfig(string Auth0Domain, string Auth0ClientId, string Auth0Audience)
    {
        public static ClientAuthConfig FromConfiguration(IConfiguration configuration) => new(
            configuration["AUTH0_DOMAIN"]?.Trim() ?? string.Empty,
            configuration["AUTH0_CLIENT_ID"]?.Trim() ?? string.Empty,
            configuration["AUTH0_AUDIENCE"]?.Trim() ?? string.Empty);

        /// <summary>
        /// The SPA can only start a login with both a domain and a client id. A domain without a
        /// client id is the half-configured state worth a startup warning: the API would validate
        /// tokens but nobody could obtain one.
        /// </summary>
        [JsonIgnore]
        public bool IsHalfConfigured =>
            !string.IsNullOrWhiteSpace(Auth0Domain) && string.IsNullOrWhiteSpace(Auth0ClientId);
    }
}
