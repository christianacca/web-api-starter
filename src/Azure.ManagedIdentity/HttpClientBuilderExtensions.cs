using Microsoft.Extensions.DependencyInjection;

namespace Mri.Azure.ManagedIdentity; 

public static class HttpClientBuilderExtensions {
  /// <summary>
  ///   Adds a <see cref="AzureIdentityAuthHttpClientHandler" /> for a named <see cref="HttpClient" />.
  /// </summary>
  /// <param name="builder">The <see cref="IHttpClientBuilder" />.</param>
  /// <param name="tokenOptionsName">
  ///   The value assigned to <see cref="AzureIdentityAuthHttpClientHandler.TokenOptionsName"/>
  /// </param>
  public static IHttpClientBuilder AddAzureIdentityAuthHttpMessageHandler(this IHttpClientBuilder builder,
    string tokenOptionsName = "") {
    return builder
      .AddHttpMessageHandler(provider => {
        var tokenServiceFactory = provider.GetRequiredService<TokenServiceFactory>();
        return new AzureIdentityAuthHttpClientHandler(tokenServiceFactory) { TokenOptionsName = tokenOptionsName };
      });
  }
}