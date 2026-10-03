namespace Humaid.RiskGovernance.AdminUI.Web.Auth
{
    /// <summary>Named authorization policies (Program.cs) for the few rules a plain role list can't
    /// express. Everything else is a role list on the action - see <c>AppRoles</c>.</summary>
    public static class AccessPolicies
    {
        /// <summary>Enumerating every user: open in local dev (it powers the "acting as" switcher),
        /// Admin-only anywhere real authentication is on.</summary>
        public const string UserDirectory = "UserDirectory";
    }
}
