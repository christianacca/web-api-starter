using Microsoft.Extensions.DependencyInjection;

namespace Template.Shared.Github;

public static class ServiceCollectionExtensions {
  public static IServiceCollection AddGithubAppOptions(this IServiceCollection services, string configurationSection) {
    services.AddOptions<GithubAppOptions>()
          .BindConfiguration(configurationSection)
          .ValidateDataAnnotations().ValidateOnStart();

    return services;
  }

  public static IServiceCollection AddGithubServices(this IServiceCollection services, string configurationSection) {
    services.AddGithubAppOptions(configurationSection);

    services.AddSingleton<IGitHubClientFactory, GitHubClientFactory>();
    return services;
  }
}
