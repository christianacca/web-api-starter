using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace Template.Shared.Github;

public static class ServiceCollectionExtensions {
  private sealed class GithubAppCredentialMarker { }

  public static IServiceCollection AddGithubAppCredentialOptions(this IServiceCollection services, string configurationSection = "Github") {
    // Marker prevents duplicate BindConfiguration/ValidateDataAnnotations registrations when multiple
    // consumers (e.g. AddGithubWorkflow) each call this method internally.
    // Unlike TryAddSingleton, this guards the AddOptions fluent chain which uses plain AddSingleton internally.
    if (services.Any(d => d.ServiceType == typeof(GithubAppCredentialMarker)))
      return services;

    services.AddSingleton<GithubAppCredentialMarker>();
    services.AddOptions<GithubAppCredentialOptions>()
      .BindConfiguration(configurationSection)
      .ValidateDataAnnotations();

    services.TryAddSingleton<IGitHubClientFactory, GitHubClientFactory>();
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
