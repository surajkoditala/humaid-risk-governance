namespace Humaid.RiskGovernance.AdminUI.UnitTests.Auth
{
    using System.Net;
    using System.Text;
    using Humaid.RiskGovernance.AdminUI.Web.Auth;
    using Microsoft.Extensions.Logging.Abstractions;
    using Moq;
    using Xunit;

    /// <summary>
    /// Guards the auto-link-by-email fallback: an email is only trustworthy for binding a caller to a
    /// pre-created app_user row if Auth0 reports it as verified, and a flaky /userinfo call must
    /// degrade to "no email" rather than failing the whole request.
    /// </summary>
    public class Auth0UserInfoClientTests
    {
        private static Auth0UserInfoClient ClientReturning(Func<HttpResponseMessage> respond)
        {
            var handler = new StubHandler(respond);
            var factory = new Mock<IHttpClientFactory>();
            factory.Setup(f => f.CreateClient("Auth0"))
                .Returns(new HttpClient(handler) { BaseAddress = new Uri("https://tenant.example/") });
            return new Auth0UserInfoClient(factory.Object, NullLogger<Auth0UserInfoClient>.Instance);
        }

        private static HttpResponseMessage Json(string body) =>
            new(HttpStatusCode.OK) { Content = new StringContent(body, Encoding.UTF8, "application/json") };

        [Fact]
        public async Task ReturnsEmailWhenAuth0ReportsItVerified()
        {
            var client = ClientReturning(() => Json("""{"email":"a@b.com","email_verified":true}"""));

            Assert.Equal("a@b.com", await client.GetEmailAsync("token"));
        }

        [Fact]
        public async Task ReturnsNullWhenEmailIsNotVerified()
        {
            var client = ClientReturning(() => Json("""{"email":"a@b.com","email_verified":false}"""));

            Assert.Null(await client.GetEmailAsync("token"));
        }

        [Fact]
        public async Task ReturnsNullWhenEmailVerifiedClaimIsMissing()
        {
            var client = ClientReturning(() => Json("""{"email":"a@b.com"}"""));

            Assert.Null(await client.GetEmailAsync("token"));
        }

        [Fact]
        public async Task ReturnsNullOnMalformedBody()
        {
            var client = ClientReturning(() => Json("not json"));

            Assert.Null(await client.GetEmailAsync("token"));
        }

        [Fact]
        public async Task ReturnsNullOnTimeout()
        {
            var client = ClientReturning(() => throw new TaskCanceledException());

            Assert.Null(await client.GetEmailAsync("token"));
        }

        [Fact]
        public async Task ReturnsNullOnNonSuccessStatus()
        {
            var client = ClientReturning(() => new HttpResponseMessage(HttpStatusCode.Unauthorized));

            Assert.Null(await client.GetEmailAsync("token"));
        }

        private sealed class StubHandler(Func<HttpResponseMessage> respond) : HttpMessageHandler
        {
            protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
                Task.FromResult(respond());
        }
    }
}
