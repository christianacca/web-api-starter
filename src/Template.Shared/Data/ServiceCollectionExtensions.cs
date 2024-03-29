using Microsoft.Extensions.DependencyInjection;

namespace Template.Shared.Data;

public static class ServiceCollectionExtensions {
  public static IServiceCollection AddEnvironmentInfoOptions(
    this IServiceCollection serviceCollection, bool isDevelopment
  ) {
    serviceCollection
      .AddOptions<EnvironmentInfoSettings>()
      .BindConfiguration("EnvironmentInfo")
      .Configure(options => {
        if (string.IsNullOrEmpty(options.EnvId) && isDevelopment) {
          options.EnvId = Environment.MachineName;
        }
      })
      .ValidateDataAnnotations();

    return serviceCollection;
  }
}