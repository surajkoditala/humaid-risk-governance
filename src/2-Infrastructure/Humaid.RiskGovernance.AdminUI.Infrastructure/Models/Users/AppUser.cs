namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Users
{
    public class AppUser
    {
        public Guid Id { get; set; }
        public string Auth0Subject { get; set; } = string.Empty;
        public string Email { get; set; } = string.Empty;
        public string DisplayName { get; set; } = string.Empty;

        /// <summary>Every role this user holds (Epic 11 follow-up: app_user_role, not a single
        /// column) - each entry is one of ProductOwner | Analyst | CommitteeMember | Admin.</summary>
        public string[] Roles { get; set; } = [];
    }
}
