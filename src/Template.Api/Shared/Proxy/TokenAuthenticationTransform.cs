using System.Net.Http.Headers;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.Extensions.Options;
using Template.Api.Shared.AzureIdentity;
using Yarp.ReverseProxy.Transforms;
using Yarp.ReverseProxy.Transforms.Builder;

namespace Template.Api.Shared.Proxy;

public class TokenAuthenticationTransform : ITransformProvider {
  public void ValidateRoute(TransformRouteValidationContext context) {
    // nothing to do
  }

  public void ValidateCluster(TransformClusterValidationContext context) {
    // nothing to do
  }

  public void Apply(TransformBuilderContext context) {
    if (context.Route.ClusterId == "FunctionsApp") {
      context.AddRequestTransform(async transformContext => {
        await AuthenticateRequest(transformContext, Options.DefaultName);
      });
    }
  }

  private static async Task AuthenticateRequest(RequestTransformContext transformContext, string tokenOptionsName) {
    var tokenService = transformContext.HttpContext.RequestServices.GetRequiredService<TokenServiceFactory>()
      .Get(tokenOptionsName);
    var token = await tokenService.GetTokenAsync(transformContext.HttpContext.RequestAborted);
    transformContext.ProxyRequest.Headers.Authorization =
      new AuthenticationHeaderValue(JwtBearerDefaults.AuthenticationScheme, token);

    var originalAuthHeader = transformContext.HttpContext.Request.Headers.Authorization.ToString();
    if (!string.IsNullOrEmpty(originalAuthHeader)) {
      transformContext.ProxyRequest.Headers.Add(HeaderNames.OriginalAuthorization, originalAuthHeader);
    }
  }
}