using Mri.Azure.ManagedIdentity;
using Template.Api.Shared.Http;

namespace Template.Api.Shared.Proxy; 

public static class ServiceCollectionExtensions {
  public static IHttpClientBuilder AddProxyHttpClient<T>(this IServiceCollection serviceCollection, Action<HttpClient> action) where T : class {
    return AddProxyHttpClient<T>(serviceCollection, action, "");
  }

  public static IHttpClientBuilder AddProxyHttpClient<T>(this IServiceCollection serviceCollection, Action<HttpClient> action, string tokenOptionsName) where T : class {
    return serviceCollection
      .AddHttpClient<T>(action)
      .AddHttpMessageHandler<HeaderForwardingHttpClientHandler>()
      .AddAzureIdentityAuthHttpMessageHandler(tokenOptionsName)
      .AddEnrichOriginServerExceptionHandler();
  }

  public static IHttpClientBuilder AddProxyHttpClient<T>(this IServiceCollection serviceCollection, string url) where T : class {
    return AddProxyHttpClient<T>(serviceCollection, url, "");
  }

  public static IHttpClientBuilder AddProxyHttpClient<T>(this IServiceCollection serviceCollection, string url, string tokenOptionsName) where T : class {
    return serviceCollection.AddProxyHttpClient<T>(client => client.BaseAddress = new Uri(url), tokenOptionsName);
  }
}