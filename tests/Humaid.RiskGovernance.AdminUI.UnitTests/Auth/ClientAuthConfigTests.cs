namespace Humaid.RiskGovernance.AdminUI.UnitTests.Auth
{
    using System.Text.Json;
    using Humaid.RiskGovernance.AdminUI.Web.Auth;
    using Microsoft.Extensions.Configuration;
    using Xunit;

    /// <summary>
    /// /config.json is how the SPA learns its Auth0 settings at runtime. The webapp's
    /// authConfig.js reads exactly these camelCase keys, so the shape is part of the contract.
    /// </summary>
    public class ClientAuthConfigTests
    {
        private static IConfiguration ConfigurationWith(params (string Key, string? Value)[] values) =>
            new ConfigurationBuilder()
                .AddInMemoryCollection(values.Select(v => new KeyValuePair<string, string?>(v.Key, v.Value)))
                .Build();

        [Fact]
        public void ReadsAllThreeValuesFromConfiguration()
        {
            var config = ClientAuthConfig.FromConfiguration(ConfigurationWith(
                ("AUTH0_DOMAIN", "tenant.us.auth0.com"),
                ("AUTH0_CLIENT_ID", "client-123"),
                ("AUTH0_AUDIENCE", "https://api.example")));

            Assert.Equal("tenant.us.auth0.com", config.Auth0Domain);
            Assert.Equal("client-123", config.Auth0ClientId);
            Assert.Equal("https://api.example", config.Auth0Audience);
        }

        [Fact]
        public void MissingValuesBecomeEmptyStringsNotNulls()
        {
            var config = ClientAuthConfig.FromConfiguration(ConfigurationWith());

            Assert.Equal(string.Empty, config.Auth0Domain);
            Assert.Equal(string.Empty, config.Auth0ClientId);
            Assert.Equal(string.Empty, config.Auth0Audience);
        }

        [Fact]
        public void TrimsStrayWhitespaceFromPortalCopyPaste()
        {
            var config = ClientAuthConfig.FromConfiguration(ConfigurationWith(("AUTH0_DOMAIN", "  tenant.us.auth0.com \n")));

            Assert.Equal("tenant.us.auth0.com", config.Auth0Domain);
        }

        [Fact]
        public void SerializesWithTheCamelCaseKeysTheWebappReads()
        {
            var config = new ClientAuthConfig("d", "c", "a");

            var json = JsonSerializer.Serialize(config, new JsonSerializerOptions(JsonSerializerDefaults.Web));

            Assert.Equal("""{"auth0Domain":"d","auth0ClientId":"c","auth0Audience":"a"}""", json);
        }

        [Theory]
        [InlineData("tenant.us.auth0.com", "", true)]
        [InlineData("tenant.us.auth0.com", "client-123", false)]
        [InlineData("", "", false)]
        public void FlagsOnlyTheDomainWithoutClientIdState(string domain, string clientId, bool expected)
        {
            var config = new ClientAuthConfig(domain, clientId, "aud");

            Assert.Equal(expected, config.IsHalfConfigured);
        }
    }
}
