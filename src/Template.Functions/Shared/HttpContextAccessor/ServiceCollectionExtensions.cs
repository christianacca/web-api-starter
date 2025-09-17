using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;

namespace Template.Functions.Shared.HttpContextAccessor;

public static class ServiceCollectionExtensions {
  /// <summary>
  /// Add <see cref="IHttpContextAccessor"/> service to access the current <see cref="HttpContext"/> in Azure Functions.
  /// </summary>
  public static IServiceCollection AddFunctionHttpContextAccessor(this IServiceCollection services)
    => services.AddSingleton<IHttpContextAccessor, FunctionHttpContextAccessor>();
}