using System.Net.Http.Headers;
using Microsoft.Extensions.Options;

namespace Mri.Azure.ManagedIdentity;

/// <summary>
///   A message handler that will acquire an access token using a <see cref="ITokenService" /> and add this
///   as an auth header to thus authenticate all requests made by a <see cref="HttpClient"/>
/// </summary>
public class AzureIdentityAuthHttpClientHandler : DelegatingHandler {
  private TokenServiceFactory TokenServiceFactory { get; }

  /// <summary>
  ///   The option name that identifies the instance of a <see cref="ITokenService" /> and it's configuration that will
  ///   be used to acquire the access token
  /// </summary>
  public virtual string TokenOptionsName { get; set; } = Options.DefaultName;

  public AzureIdentityAuthHttpClientHandler(TokenServiceFactory tokenServiceFactory) {
    TokenServiceFactory = tokenServiceFactory;
  }

  protected override async Task<HttpResponseMessage> SendAsync(
    HttpRequestMessage request, CancellationToken cancellationToken) {
    var tokenService = TokenServiceFactory.Get(TokenOptionsName);
    var token = await tokenService.GetTokenAsync(cancellationToken);
    request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
    return await base.SendAsync(request, cancellationToken);
  }
}