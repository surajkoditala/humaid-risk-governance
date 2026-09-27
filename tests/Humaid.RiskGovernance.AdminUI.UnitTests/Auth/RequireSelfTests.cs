namespace Humaid.RiskGovernance.AdminUI.UnitTests.Auth
{
    using System.Security.Claims;
    using Humaid.RiskGovernance.AdminUI.Web.Auth;
    using Humaid.RiskGovernance.AdminUI.Web.Controllers.Core;
    using Microsoft.AspNetCore.Http;
    using Microsoft.AspNetCore.Mvc;
    using Microsoft.Extensions.Logging.Abstractions;
    using Xunit;

    /// <summary>
    /// Epic 11 (closes DEF-002): a bare test controller exercising <see
    /// cref="BaseApiController.RequireSelf{T}"/> directly - every write action in the product
    /// controllers calls this first with the actor id from its own request body/form, so its
    /// behaviour is worth pinning on its own rather than only indirectly through each controller.
    /// </summary>
    public class RequireSelfTests
    {
        private class TestController : BaseApiController
        {
            public TestController() : base(NullLogger<TestController>.Instance) { }

            public OperationResultLike<T> Call<T>(Guid claimedUserId) =>
                new(RequireSelf<T>(claimedUserId));
        }

        public record OperationResultLike<T>(Infrastructure.Models.Core.OperationResult<T>? Result);

        private static TestController ControllerActingAs(Guid? appUserId)
        {
            var claims = new List<Claim>();
            if (appUserId is not null)
                claims.Add(new Claim(AppClaimTypes.UserId, appUserId.Value.ToString()));

            var controller = new TestController
            {
                ControllerContext = new ControllerContext
                {
                    HttpContext = new DefaultHttpContext
                    {
                        User = new ClaimsPrincipal(new ClaimsIdentity(claims, "TestScheme")),
                    },
                },
            };
            return controller;
        }

        [Fact]
        public void AllowsActingAsSelf()
        {
            var userId = Guid.NewGuid();
            var controller = ControllerActingAs(userId);

            var result = controller.Call<string>(userId);

            Assert.Null(result.Result);
        }

        [Fact]
        public void RejectsActingAsSomeoneElse()
        {
            var caller = Guid.NewGuid();
            var claimedActor = Guid.NewGuid();
            var controller = ControllerActingAs(caller);

            var result = controller.Call<string>(claimedActor);

            Assert.NotNull(result.Result);
            Assert.True(result.Result!.IsForbidden);
        }

        [Fact]
        public void RejectsWhenCallerHasNoResolvedAppUser()
        {
            var controller = ControllerActingAs(appUserId: null);

            var result = controller.Call<string>(Guid.NewGuid());

            Assert.NotNull(result.Result);
            Assert.True(result.Result!.IsForbidden);
        }
    }
}
