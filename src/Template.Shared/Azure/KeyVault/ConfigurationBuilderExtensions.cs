using Azure.Extensions.AspNetCore.Configuration.Secrets;
using Azure.Identity;
using Microsoft.Extensions.Configuration;

namespace Template.Shared.Azure.KeyVault; 

public static class ConfigurationBuilderExtensions {
  /// <summary>
  /// Adds an <see cref="IConfigurationProvider"/> that reads configuration values from the Azure KeyVault
  /// </summary>
  /// <param name="builder">The <see cref="IConfigurationBuilder"/> to add to</param>
  /// <param name="settings">
  /// The settings that provide managed identity credentials and options that configure the provider
  /// </param>
  /// <example>
  /// <code lang="c#">
  /// void ConfigureConfiguration(ConfigurationManager configuration) {s
  ///   configuration.AddAzureKeyVault(configuration.GetSection("Api").Get&lt;KeyVaultSettings>());
  /// }
  /// </code>
  /// </example>
  public static IConfigurationBuilder AddAzureKeyVault(
    this IConfigurationBuilder builder, KeyVaultSettings? settings
  ) {
    if (settings is { IsEnabled: true }) {
      builder.AddAzureKeyVault(
        new Uri($"https://{settings.KeyVaultName}.vault.azure.net/"),
        new DefaultAzureCredential(settings.DefaultAzureCredentials),
        new AzureKeyVaultConfigurationOptions {
          Manager = new FilteredKeyVaultSecretManager {
            Sections = settings.KeyVaultSections
          },
          ReloadInterval = settings.KeyVaultReloadInterval
        }
      );
    }

    return builder;
  }

  /// <summary>
  /// Adds an <see cref="IConfigurationProvider"/> that reads configuration values from the Azure KeyVault
  /// </summary>
  /// <param name="builder">The <see cref="IConfigurationBuilder"/> to add to</param>
  /// <param name="configuration">
  /// The existing configuration for the app that will be used to find the settings used to configure the key vault
  /// configuration provider
  /// </param>
  /// <param name="sectionName">
  /// The name of the section within <paramref name="configuration"/> that defines the key vault provider settings
  /// </param>
  /// <param name="includeSectionName">
  /// Whether to include the <paramref name="sectionName"/> as a value in <see cref="KeyVaultSettings.KeyVaultSections"/>.
  /// Defaults to <c>false</c>
  /// </param>
  public static IConfigurationBuilder AddAzureKeyVault(
    this IConfigurationBuilder builder, IConfiguration configuration, string sectionName, bool includeSectionName = false
  ) {
    var settings = configuration.GetSection(sectionName).Get<KeyVaultSettings>();
    if (settings != null && includeSectionName) {
      settings.KeyVaultSections =
        (settings.KeyVaultSections ?? Enumerable.Empty<string>()).Union([sectionName]).ToList();
    }

    return builder.AddAzureKeyVault(settings);
  }
}