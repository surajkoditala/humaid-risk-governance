namespace Humaid.RiskGovernance.AdminUI.Web.Auth
{
    using System.Net.Http.Headers;
    using System.Net.Http.Json;
    using System.Text.Json.Serialization;

    /// <summary>
    /// Epic 11 follow-up: calls Auth0's own /userinfo endpoint with the caller's own access token to
    /// get their verified email. The access token issued for this API's custom audience doesn't
    /// carry an email claim by default - only a tenant-side Auth0 Action could add one, which is
    /// outside this repo - so this asks Auth0 directly instead, authoritative and requiring no
    /// tenant config change. See AppUserClaimsTransformation for the one place this is called: only
    /// as a fallback for a caller whose subject matches no app_user row yet.
    /// </summary>
    public interface IAuth0UserInfoClient
    {
        Task<string?> GetEmailAsync(string accessToken, CancellationToken cancellationToken = default);
    }

    public class Auth0UserInfoClient : IAuth0UserInfoClient
    {
        private readonly HttpClient _httpClient;
        private readonly ILogger<Auth0UserInfoClient> _logger;

        public Auth0UserInfoClient(IHttpClientFactory httpClientFactory, ILogger<Auth0UserInfoClient> logger)
        {
            _httpClient = httpClientFactory.CreateClient("Auth0");
            _logger = logger;
        }

        public async Task<string?> GetEmailAsync(string accessToken, CancellationToken cancellationToken = default)
        {
            try
            {
                using var request = new HttpRequestMessage(HttpMethod.Get, "userinfo");
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
                using var response = await _httpClient.SendAsync(request, cancellationToken);
                if (!response.IsSuccessStatusCode)
                {
                    return null;
                }
                var profile = await response.Content.ReadFromJsonAsync<Auth0UserInfo>(cancellationToken: cancellationToken);
                return profile?.Email;
            }
            catch (HttpRequestException ex)
            {
                // Best-effort: Auth0 being unreachable just means the fallback fails and the caller
                // stays unprovisioned this request, same as today - never blocks the request itself.
                _logger.LogWarning(ex, "Could not reach Auth0's /userinfo endpoint to resolve the caller's email.");
                return null;
            }
        }

        private record Auth0UserInfo([property: JsonPropertyName("email")] string? Email);
    }
}
