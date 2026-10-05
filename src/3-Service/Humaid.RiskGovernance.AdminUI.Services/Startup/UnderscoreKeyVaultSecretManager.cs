namespace Humaid.RiskGovernance.AdminUI.Services.Startup
{
    using Azure.Extensions.AspNetCore.Configuration.Secrets;
    using Azure.Security.KeyVault.Secrets;

    /// <summary>
    /// Maps Key Vault secret names (hyphenated, e.g. ANTHROPIC-API-KEY) onto this app's config
    /// keys (underscored, e.g. ANTHROPIC_API_KEY - the same screaming-snake-case every other env
    /// var in this codebase uses), and restricts which secrets get loaded to an explicit
    /// allow-list. The dev environment provisions a single Key Vault shared by both the Workbench
    /// and Mock Systems container apps - without an allow-list, whichever app's managed identity
    /// has read access would pull every secret in the vault into its own IConfiguration,
    /// including ones that belong to the other app or to unrelated infra.
    /// </summary>
    public class UnderscoreKeyVaultSecretManager : KeyVaultSecretManager
    {
        private readonly HashSet<string> _allowedSecretNames;

        public UnderscoreKeyVaultSecretManager(IEnumerable<string> allowedSecretNames)
        {
            _allowedSecretNames = new HashSet<string>(allowedSecretNames, StringComparer.OrdinalIgnoreCase);
        }

        public override bool Load(SecretProperties secret) => _allowedSecretNames.Contains(secret.Name);

        public override string GetKey(KeyVaultSecret secret) => secret.Name.Replace('-', '_');
    }
}
