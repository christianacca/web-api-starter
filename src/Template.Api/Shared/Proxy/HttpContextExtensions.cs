using Yarp.ReverseProxy.Model;

namespace Template.Api.Shared.Proxy;

public static class HttpContextExtensions {
  public static bool IsProxiedRequest(this HttpContext context) {
    return context.GetEndpoint()?.Metadata.GetMetadata<RouteModel>() != null;
  }
}