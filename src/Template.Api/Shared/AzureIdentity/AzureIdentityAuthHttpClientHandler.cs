using System.Net.Http.Headers;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.Extensions.Options;

namespace Template.Api.Shared.AzureIdentity;

public class AzureIdentityAuthHttpClientHandler : DelegatingHandler {
  private IHttpContextAccessor HttpContextAccessor { get; }
  protected virtual string TokenOptionsName { get; set; } = Options.DefaultName;

  public AzureIdentityAuthHttpClientHandler(IHttpContextAccessor httpContextAccessor) {
    HttpContextAccessor = httpContextAccessor;
  }

  protected override async Task<HttpResponseMessage> SendAsync(
    HttpRequestMessage request, CancellationToken cancellationToken) {
    var httpContext = HttpContextAccessor.HttpContext;
    if (httpContext != null) {
      var tokenService = httpContext.RequestServices.GetRequiredService<TokenServiceFactory>().Get(TokenOptionsName);
      var token = await tokenService.GetTokenAsync(cancellationToken);
      request.Headers.Authorization =
        new AuthenticationHeaderValue(JwtBearerDefaults.AuthenticationScheme, token);
    }

    return await base.SendAsync(request, cancellationToken);
  }
}