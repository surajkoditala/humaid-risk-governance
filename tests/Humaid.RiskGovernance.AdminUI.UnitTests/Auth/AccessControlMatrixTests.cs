namespace Humaid.RiskGovernance.AdminUI.UnitTests.Auth
{
    using System.Reflection;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Users;
    using Humaid.RiskGovernance.AdminUI.Web.Controllers.Core;
    using Humaid.RiskGovernance.AdminUI.Web.Controllers.Users;
    using Microsoft.AspNetCore.Authorization;
    using Microsoft.AspNetCore.Mvc;
    using Xunit;

    /// <summary>
    /// Epic 11 (US-11.1 AC4): "a documented matrix maps each role to every action, and each endpoint
    /// behaviour matches it". docs/governance/access-control-matrix.md is that matrix, written for a
    /// person; this pins the same claim against the code by reflecting over every controller action
    /// in the Web project.
    /// <para>
    /// A bare <c>[Authorize]</c> (no Roles, no Policy) permits every one of the four roles - that is
    /// exactly the gap Epic 11 was raised to close (DEF-002: a Product Owner's vote counted toward
    /// committee quorum because nothing checked who was allowed to vote). This test fails the moment
    /// a new action ships without a role or policy restriction, instead of that surfacing later as a
    /// QA-found defect.
    /// </para>
    /// </summary>
    public class AccessControlMatrixTests
    {
        // Every deliberate exception, with the reason inline - never add to this list without one.
        private static readonly (Type Controller, string Action, string Reason)[] Exemptions =
        [
            (typeof(PingController), nameof(PingController.Get),
                "Documented reference vertical slice - callable before Auth0 is even configured."),
            (typeof(UserController), nameof(UserController.GetMe),
                "Returns only the caller's own resolved identity - every authenticated role may call it."),
        ];

        private static readonly Type[] HttpMethodAttributeTypes =
        [
            typeof(HttpGetAttribute), typeof(HttpPostAttribute), typeof(HttpPutAttribute),
            typeof(HttpDeleteAttribute), typeof(HttpPatchAttribute),
        ];

        private static IEnumerable<(Type Controller, MethodInfo Action)> AllActions()
        {
            var assembly = typeof(BaseApiController).Assembly;

            foreach (var controller in assembly.GetTypes())
            {
                if (!controller.IsPublic || controller.IsAbstract || !typeof(ControllerBase).IsAssignableFrom(controller))
                    continue;

                foreach (var method in controller.GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly))
                {
                    if (method.GetCustomAttributes().Any(a => HttpMethodAttributeTypes.Contains(a.GetType())))
                        yield return (controller, method);
                }
            }
        }

        private static bool IsExempt(Type controller, MethodInfo action) =>
            Exemptions.Any(e => e.Controller == controller && e.Action == action.Name);

        [Fact]
        public void EveryControllerActionExists()
        {
            // A sanity check on the reflection itself - if this ever hits zero, the two tests below
            // are passing on an empty set, not because access control is actually fine.
            Assert.True(AllActions().Count() > 30, "Expected to find the full set of controller actions via reflection.");
        }

        [Fact]
        public void EveryControllerActionDeclaresARoleOrPolicyRestriction()
        {
            var violations = new List<string>();

            foreach (var (controller, action) in AllActions())
            {
                if (IsExempt(controller, action)) continue;

                if (action.GetCustomAttribute<AllowAnonymousAttribute>() is not null ||
                    controller.GetCustomAttribute<AllowAnonymousAttribute>() is not null)
                {
                    violations.Add($"{controller.Name}.{action.Name} is [AllowAnonymous] - not a documented exemption.");
                    continue;
                }

                // ASP.NET Core requires the caller to satisfy EVERY [Authorize] attribute present
                // (class-level AND method-level, if both exist) - so it is enough for either one to
                // carry a real restriction, but a controller must not rely on a class-level Roles
                // attribute while narrowing per method (see CategoryMappingController's own comment).
                var classAuthorize = controller.GetCustomAttributes<AuthorizeAttribute>().ToList();
                var methodAuthorize = action.GetCustomAttributes<AuthorizeAttribute>().ToList();

                if (classAuthorize.Count == 0 && methodAuthorize.Count == 0)
                {
                    violations.Add($"{controller.Name}.{action.Name} has no [Authorize] at all.");
                    continue;
                }

                var hasClassRoles = classAuthorize.Any(a => !string.IsNullOrWhiteSpace(a.Roles));
                var hasRestriction = classAuthorize.Concat(methodAuthorize)
                    .Any(a => !string.IsNullOrWhiteSpace(a.Roles) || !string.IsNullOrWhiteSpace(a.Policy));

                if (!hasRestriction)
                {
                    violations.Add($"{controller.Name}.{action.Name} only has a bare [Authorize] (any role) - " +
                        "add Roles or Policy, or add it to AccessControlMatrixTests.Exemptions with a reason.");
                }
                else if (hasClassRoles && methodAuthorize.Any(a => !string.IsNullOrWhiteSpace(a.Roles)))
                {
                    // Both present: ASP.NET Core ANDs them, so a method-level Roles list can only ever
                    // narrow a class-level one, never widen it. If that is not the intent, the method
                    // is not getting the access its own attribute claims.
                    violations.Add($"{controller.Name}.{action.Name} has Roles on both the controller and the " +
                        "action - the effective access is their intersection, not the method's own list. " +
                        "Give the controller a bare [Authorize] instead (see CategoryMappingController).");
                }
            }

            Assert.True(violations.Count == 0, "Action(s) with a missing or unreliable role/policy restriction:\n" + string.Join("\n", violations));
        }

        [Fact]
        public void EveryDeclaredRoleIsAKnownAppRole()
        {
            var violations = new List<string>();

            foreach (var (controller, action) in AllActions())
            {
                var roleLists = controller.GetCustomAttributes<AuthorizeAttribute>()
                    .Concat(action.GetCustomAttributes<AuthorizeAttribute>())
                    .Select(a => a.Roles)
                    .Where(r => !string.IsNullOrWhiteSpace(r));

                foreach (var roles in roleLists)
                {
                    foreach (var role in roles!.Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries))
                    {
                        if (!AppRoles.All.Contains(role))
                            violations.Add($"{controller.Name}.{action.Name} declares unknown role '{role}'.");
                    }
                }
            }

            Assert.True(violations.Count == 0, string.Join("\n", violations));
        }
    }
}
