using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.FeatureManagement;

namespace Template.Api.Endpoints.FeatureFlags;

[ApiController]
[Route("api/[controller]")]
[AllowAnonymous]
public class FeatureFlagsController(IVariantFeatureManager featureManager) : ControllerBase {
  private async Task<FeatureFlagModel> CheckFeatureAsync(string featureName, CancellationToken ct) {
    return new FeatureFlagModel { Name = featureName, Enabled = await featureManager.IsEnabledAsync(featureName, ct) };
  }

  [HttpGet]
  [ProducesResponseType(StatusCodes.Status200OK)]
  public async Task<IEnumerable<FeatureFlagModel>> Get(CancellationToken ct) {
    var featureNames = await featureManager.GetFeatureNamesAsync(ct).ToListAsync(ct);
    var featureValueTasks = featureNames.Select(featureName => CheckFeatureAsync(featureName, ct));
    return await Task.WhenAll(featureValueTasks);
  }
}