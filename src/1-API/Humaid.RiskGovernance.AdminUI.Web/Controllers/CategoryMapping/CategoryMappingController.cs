namespace Humaid.RiskGovernance.AdminUI.Web.Controllers.CategoryMapping
{
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Services.CategoryMapping;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.CategoryMapping;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Core;
    using Humaid.RiskGovernance.AdminUI.Infrastructure.Models.Users;
    using Humaid.RiskGovernance.AdminUI.Web.Controllers.Core;
    using Microsoft.AspNetCore.Authorization;
    using Microsoft.AspNetCore.Mvc;

    /// <summary>Epic 2 - Risk Categorization &amp; Framework Mapping. No class-level Roles: Categories
    /// (below) needs a wider role list than the rest of this controller, and ASP.NET Core ANDs a
    /// class-level [Authorize(Roles=...)] with a method-level one rather than the method overriding
    /// it - each action states its own roles instead.</summary>
    [Authorize]
    [Route("api/[controller]")]
    public class CategoryMappingController : BaseApiController
    {
        private readonly ICategoryMappingService _categoryMappingService;

        public CategoryMappingController(ICategoryMappingService categoryMappingService, ILogger<CategoryMappingController> logger)
            : base(logger)
        {
            _categoryMappingService = categoryMappingService;
        }

        /// <summary>US-2.1: real Claude call, grounded against the change type's category defaults.</summary>
        [HttpPost("Propose")]
        [Authorize(Roles = AppRoles.Analyst)]
        public Task<IActionResult> Propose([FromQuery] Guid assessmentId, [FromQuery] Guid changeRequestId) =>
            ExecuteAsync(async () =>
            {
                var mapping = await _categoryMappingService.ProposeAsync(assessmentId, changeRequestId);
                return OperationResult<IReadOnlyList<Infrastructure.Models.CategoryMapping.CategoryMapping>>.Success(mapping);
            }, "Failed to propose category mapping.");

        /// <summary>US-2.2: reason mandatory - enforced by func_overrideCategoryMapping.</summary>
        [HttpPost("Override")]
        [Authorize(Roles = AppRoles.Analyst)]
        public Task<IActionResult> Override([FromBody] OverrideCategoryMappingInput input) =>
            ExecuteAsync(async () =>
            {
                if (RequireSelf<Guid>(input.ActorUserId) is { } forbidden) return forbidden;

                try
                {
                    var id = await _categoryMappingService.OverrideAsync(input);
                    return OperationResult<Guid>.Success(id);
                }
                catch (Exception ex) when (ex.Message.Contains("reason is required", StringComparison.OrdinalIgnoreCase))
                {
                    return OperationResult<Guid>.BadRequest(ex.Message);
                }
            }, "Failed to override category mapping.");

        /// <summary>All framework categories, for the "add a category" control (US-2.2) - not just
        /// what func_getChangeTypeCategoryDefaults would have suggested for this change type. Also
        /// backs the category dropdown on the Admin-only scoring configuration screen (US-10.1).</summary>
        [HttpGet("Categories")]
        [Authorize(Roles = AppRoles.AnalystOrAdmin)]
        public Task<IActionResult> GetAllCategories() =>
            ExecuteAsync(async () =>
            {
                var categories = await _categoryMappingService.GetAllRiskCategoriesAsync();
                return OperationResult<IReadOnlyList<Infrastructure.Models.RiskFramework.RiskCategory>>.Success(categories);
            }, "Failed to fetch risk categories.");

        [HttpGet("{assessmentId:guid}")]
        [Authorize(Roles = AppRoles.Analyst)]
        public Task<IActionResult> GetMapping(Guid assessmentId) =>
            ExecuteAsync(async () =>
            {
                var mapping = await _categoryMappingService.GetMappingAsync(assessmentId);
                return OperationResult<IReadOnlyList<Infrastructure.Models.CategoryMapping.CategoryMapping>>.Success(mapping);
            }, "Failed to fetch category mapping.");
    }
}
