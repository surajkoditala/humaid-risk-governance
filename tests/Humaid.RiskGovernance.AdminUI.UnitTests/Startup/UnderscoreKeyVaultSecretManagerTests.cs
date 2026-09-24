namespace Humaid.RiskGovernance.AdminUI.UnitTests.Startup
{
    using Azure.Security.KeyVault.Secrets;
    using Humaid.RiskGovernance.AdminUI.Services.Startup;
    using Xunit;

    /// <summary>
    /// Regression guard for a real bug caught during PR review: without an allow-list, this
    /// manager would load every secret in the shared dev Key Vault (both the Workbench's and
    /// Mock Systems' apps read from the same vault) instead of just the ones an app actually
    /// expects - see the class's own comment.
    /// </summary>
    public class UnderscoreKeyVaultSecretManagerTests
    {
        [Theory]
        [InlineData("ANTHROPIC-API-KEY", "ANTHROPIC_API_KEY")]
        [InlineData("FOUNDRY-API-KEY", "FOUNDRY_API_KEY")]
        [InlineData("ALREADY_UNDERSCORED", "ALREADY_UNDERSCORED")]
        [InlineData("mixed-Name_here", "mixed_Name_here")]
        public void GetKey_ReplacesHyphensWithUnderscores(string secretName, string expectedKey)
        {
            var sut = new UnderscoreKeyVaultSecretManager([secretName]);
            var secret = new KeyVaultSecret(secretName, "value");

            Assert.Equal(expectedKey, sut.GetKey(secret));
        }

        [Fact]
        public void Load_AcceptsOnlyAllowListedSecretNames()
        {
            var sut = new UnderscoreKeyVaultSecretManager(["ANTHROPIC-API-KEY", "FOUNDRY-API-KEY"]);

            Assert.True(sut.Load(new SecretProperties("ANTHROPIC-API-KEY")));
            Assert.True(sut.Load(new SecretProperties("FOUNDRY-API-KEY")));
            Assert.False(sut.Load(new SecretProperties("SOME-OTHER-APPS-SECRET")));
        }

        [Fact]
        public void Load_IsCaseInsensitive()
        {
            var sut = new UnderscoreKeyVaultSecretManager(["ANTHROPIC-API-KEY"]);

            Assert.True(sut.Load(new SecretProperties("anthropic-api-key")));
        }

        [Fact]
        public void Load_RejectsEverythingWhenAllowListIsEmpty()
        {
            var sut = new UnderscoreKeyVaultSecretManager([]);

            Assert.False(sut.Load(new SecretProperties("ANTHROPIC-API-KEY")));
        }
    }
}
