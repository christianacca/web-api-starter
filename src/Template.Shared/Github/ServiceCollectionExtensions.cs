using Microsoft.Extensions.DependencyInjection;

namespace Template.Shared.Github;

public static class ServiceCollectionExtensions {
  public static IServiceCollection AddGithubAppOptions(this IServiceCollection services, string configurationSection) {
    services.AddOptions<GithubAppOptions>()
      .BindConfiguration(configurationSection)
      .ValidateDataAnnotations();

    return services;
  }

  public static IServiceCollection AddGithubServices(this IServiceCollection services, string configurationSection) {
    services.AddGithubAppOptions(configurationSection);

    services.AddSingleton<IGitHubClientFactory, GitHubClientFactory>();
    return services;
  }

  /// <summary>
  /// Registers GitHub workflow services including the <see cref="FunctionAppName"/> used to prefix
  /// durable orchestration workflow run names.
  /// </summary>
  /// <param name="services">The service collection to configure.</param>
  /// <param name="configurationSection">The configuration section name for <see cref="GithubAppOptions"/>.</param>
  /// <param name="functionAppName">
  /// The name of the function app that dispatches and receives GitHub workflow callbacks.
  /// Must match the corresponding sub-product key in the product conventions.
  /// </param>
  public static IServiceCollection AddGithubWorkflow(
    this IServiceCollection services,
    string configurationSection,
    string functionAppName) {
    services.AddGithubServices(configurationSection);
    services.AddSingleton(new FunctionAppName(functionAppName));
    return services;
  }
}
