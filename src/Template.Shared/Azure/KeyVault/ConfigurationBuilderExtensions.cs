using Azure.Extensions.AspNetCore.Configuration.Secrets;
using Azure.Identity;
using Microsoft.Extensions.Configuration;

namespace Template.Shared.Azure.KeyVault; 

public static class ConfigurationBuilderExtensions {
  public static IConfigurationBuilder AddAzureKeyVault(
    this IConfigurationBuilder configuration, IConfiguration configurationSection
  ) {
    var settings = configurationSection.Get<KeyVaultSettings>();
    if (settings.IsEnabled) {
      configuration.AddAzureKeyVault(
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

    return configuration;
  }
}