namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Users
{
    /// <summary>
    /// Epic 11 - the role names an <see cref="AppUser"/> can hold. They must match the
    /// <c>app_user.role</c> CHECK constraint (schema/003_users.sql). Every controller action
    /// declares the roles allowed to call it with <c>[Authorize(Roles = ...)]</c> using these
    /// constants; the full action-by-role table is docs/governance/access-control-matrix.md and is
    /// pinned by AccessControlMatrixTests.
    /// <para>
    /// <see cref="Admin"/> is the "FCRM Analyst with configuration privileges" of US-10.1/US-10.2:
    /// it owns platform configuration and nothing in the assessment or voting workflow, so the
    /// person who tunes the scoring rules is never the person who scores or votes.
    /// </para>
    /// </summary>
    public static class AppRoles
    {
        public const string ProductOwner = "ProductOwner";
        public const string Analyst = "Analyst";
        public const string CommitteeMember = "CommitteeMember";
        public const string Admin = "Admin";

        // Comma-separated any-of lists, for [Authorize(Roles = ...)] - attribute arguments must be
        // compile-time constants, so these are spelled out rather than built from a collection.
        public const string AnalystOrCommittee = Analyst + "," + CommitteeMember;
        public const string AnalystOrAdmin = Analyst + "," + Admin;
        public const string ProductOwnerOrAnalyst = ProductOwner + "," + Analyst;
        public const string AnyRole = ProductOwner + "," + Analyst + "," + CommitteeMember + "," + Admin;

        public static readonly IReadOnlyList<string> All = [ProductOwner, Analyst, CommitteeMember, Admin];
    }
}
