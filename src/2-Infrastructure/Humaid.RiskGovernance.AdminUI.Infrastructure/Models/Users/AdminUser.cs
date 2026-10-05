namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Users
{
    /// <summary>Admin user-management screen - every user regardless of active status, with the
    /// raw Auth0 subject (null until that person's real login is linked). Distinct from
    /// <see cref="AppUser"/>, which exists to resolve a caller's own identity and so deliberately
    /// excludes anyone inactive or roleless.</summary>
    public class AdminUserSummary
    {
        public Guid Id { get; set; }
        public string? Auth0Subject { get; set; }
        public string Email { get; set; } = string.Empty;
        public string DisplayName { get; set; } = string.Empty;
        public string[] Roles { get; set; } = [];
        public bool IsActive { get; set; }
        public DateTimeOffset CreatedAt { get; set; }
    }

    public class CreateUserInput
    {
        public string Email { get; set; } = string.Empty;
        public string DisplayName { get; set; } = string.Empty;
        public string[] Roles { get; set; } = [];
        public string Reason { get; set; } = string.Empty;
        public Guid ActorUserId { get; set; }
    }

    public class SetUserRolesInput
    {
        public Guid UserId { get; set; }
        public string[] Roles { get; set; } = [];
        public string Reason { get; set; } = string.Empty;
        public Guid ActorUserId { get; set; }
    }

    public class SetUserActiveInput
    {
        public Guid UserId { get; set; }
        public bool IsActive { get; set; }
        public string Reason { get; set; } = string.Empty;
        public Guid ActorUserId { get; set; }
    }

    public class SetUserAuth0SubjectInput
    {
        public Guid UserId { get; set; }
        public string Auth0Subject { get; set; } = string.Empty;
        public string Reason { get; set; } = string.Empty;
        public Guid ActorUserId { get; set; }
    }
}
