using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

namespace Template.Functions.Shared.FunctionContextAccessor;

public static class FunctionAccessorExtensions {
  /// <summary>
  /// Add middleware to make the current <see cref="FunctionContext"/> available via <see cref="IFunctionContextAccessor"/>
  /// </summary>
  public static IFunctionsWorkerApplicationBuilder UseFunctionContextAccessor(
    this IFunctionsWorkerApplicationBuilder appBuilder
  ) =>
    appBuilder.UseMiddleware<FunctionContextMiddleware>();

  /// <summary>
  /// Add <see cref="IFunctionContextAccessor"/> service
  /// </summary>
  public static IServiceCollection AddFunctionContextAccessor(this IServiceCollection services)
    => services.AddSingleton<IFunctionContextAccessor, DefaultFunctionContextAccessor>();
}