using Microsoft.Extensions.DependencyInjection;

namespace Template.Shared.Github;

public static class ServiceCollectionExtensions {
  public static IServiceCollection AddGithubAppCredentialOptions(this IServiceCollection services, string configurationSection = "Github") {
    services.AddOptions<GithubAppCredentialOptions>()
      .BindConfiguration(configurationSection)
      .ValidateDataAnnotations();

    services.AddSingleton<IGitHubClientFactory, GitHubClientFactory>();
    return services;
  }

  /// <summary>
  /// Registers GitHub workflow services including the <see cref="FunctionAppName"/> used to prefix
  /// durable orchestration workflow run names.
  /// </summary>
  /// <param name="services">The service collection to configure.</param>
  /// <param name="configurationSection">The configuration section name for <see cref="GithubWorkflowOptions"/>.</param>
  /// <param name="functionAppName">
  /// The name of the function app that dispatches and receives GitHub workflow callbacks.
  /// Must match the corresponding sub-product key in the product conventions.
  /// </param>
  public static IServiceCollection AddGithubWorkflow(
    this IServiceCollection services,
    string configurationSection,
    string functionAppName) {
    services.AddGithubAppCredentialOptions();

    services.AddOptions<GithubWorkflowOptions>()
      .BindConfiguration(configurationSection)
      .ValidateDataAnnotations();

    services.AddSingleton(new FunctionAppName(functionAppName));
    return services;
  }
}
