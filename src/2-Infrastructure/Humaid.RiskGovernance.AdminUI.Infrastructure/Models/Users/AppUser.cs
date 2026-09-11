namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Users
{
    public class AppUser
    {
        public Guid Id { get; set; }
        public string Auth0Subject { get; set; } = string.Empty;
        public string Email { get; set; } = string.Empty;
        public string DisplayName { get; set; } = string.Empty;

        /// <summary>ProductOwner | Analyst | CommitteeMember | Admin.</summary>
        public string Role { get; set; } = string.Empty;
    }
}
