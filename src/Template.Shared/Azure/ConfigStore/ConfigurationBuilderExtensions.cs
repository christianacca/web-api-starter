using Azure.Identity;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Configuration.AzureAppConfiguration;

namespace Template.Shared.Azure.ConfigStore;

public static class ConfigurationBuilderExtensions {
  /// <summary>
  /// Adds an <see cref="IConfigurationProvider"/> that reads configuration values from the Azure Configuration Store
  /// </summary>
  /// <param name="builder">The <see cref="IConfigurationBuilder"/> to add to</param>
  /// <param name="settings">
  /// The settings that provide managed identity credentials and options that configure the provider
  /// </param>
  /// <example>
  /// <code lang="c#">
  /// void ConfigureConfiguration(ConfigurationManager configuration) {s
  ///   configuration.AddAzureAppConfig(configuration.GetSection("Api").Get&lt;AppConfigStoreSettings>());
  /// }
  /// </code>
  /// </example>
  public static IConfigurationBuilder AddAzureAppConfig(
    this IConfigurationBuilder builder, AppConfigStoreSettings? settings
  ) {
    if (settings is not { IsEnabled: true }) return builder;

    builder.AddAzureAppConfiguration(opts => settings
      .ApplyConnection(opts)
      .ApplyKeySelectors(opts)
      .ApplyRefreshStrategy(opts)
      .ApplyFeatureFlags(opts)
    );

    return builder;
  }

  /// <summary>
  /// Adds an <see cref="IConfigurationProvider"/> that reads configuration values from the Azure Configuration Store
  /// </summary>
  /// <param name="builder">The <see cref="IConfigurationBuilder"/> to add to</param>
  /// <param name="configuration">
  /// The existing configuration for the app that will be used to find the settings used to configure the Azure
  /// Configuration Store configuration provider
  /// </param>
  /// <param name="sectionName">
  /// The name of the section within <paramref name="configuration"/> that defines the Azure Configuration Store provider
  /// settings
  /// </param>
  /// <param name="includeSectionName">
  /// Whether to include the <paramref name="sectionName"/> as a value in <see cref="AppConfigStoreSettings.ConfigStoreSections"/>.
  /// Defaults to <c>false</c>
  /// </param>
  public static IConfigurationBuilder AddAzureAppConfig(
    this IConfigurationBuilder builder, IConfiguration configuration, string sectionName,
    bool includeSectionName = false
  ) {
    var settings = configuration.GetSection(sectionName).Get<AppConfigStoreSettings>();
    if (settings != null && includeSectionName) {
      settings.ConfigStoreSections = settings.ConfigStoreSections.Union([sectionName]).ToList();
    }

    return builder.AddAzureAppConfig(settings);
  }

  private static AppConfigStoreSettings ApplyConnection(
    this AppConfigStoreSettings settings, AzureAppConfigurationOptions options
  ) {
    options.Connect(settings.ConfigStoreUri, new DefaultAzureCredential(settings.DefaultAzureCredentials));
    return settings;
  }

  private static void ApplyFeatureFlags(
    this AppConfigStoreSettings settings, AzureAppConfigurationOptions options
  ) {
    if (!settings.ConfigStoreFeatureFlags.Enabled) return;

    options.UseFeatureFlags(flagOptions => {
      settings.FeatureFlagSelectors.ToList().ForEach(filter => {
        flagOptions.Select(filter.KeyFilter, filter.LabelFilter);
      });
      flagOptions.SetRefreshInterval(settings.ConfigStoreFeatureFlags.RefreshInterval);
    });
  }

  private static AppConfigStoreSettings ApplyRefreshStrategy(
    this AppConfigStoreSettings settings, AzureAppConfigurationOptions options
  ) {
    if (settings.ConfigStoreRefresh.Strategy == AzureConfigStoreRefreshStrategy.None) return settings;

    options.ConfigureRefresh(refreshOptions => {
      refreshOptions.SetRefreshInterval(settings.ConfigStoreRefresh.RefreshInterval);
      switch (settings.ConfigStoreRefresh.Strategy) {
        case AzureConfigStoreRefreshStrategy.RefreshAll:
          refreshOptions.RegisterAll();
          break;
        case AzureConfigStoreRefreshStrategy.SentinelKey: {
          var sentinelKey = settings.SentinelKeySelector;
          refreshOptions.Register(sentinelKey.KeyFilter, sentinelKey.LabelFilter, refreshAll: true);
          break;
        }
        case AzureConfigStoreRefreshStrategy.SpecificKeys:
          settings.KeysToRefreshSelectors.ToList().ForEach(filter => {
            refreshOptions.Register(filter.KeyFilter, filter.LabelFilter);
          });
          break;
      }
    });

    return settings;
  }

  private static AppConfigStoreSettings ApplyKeySelectors(
    this AppConfigStoreSettings settings, AzureAppConfigurationOptions options
  ) {
    settings.KeySelectors.ToList().ForEach(filter => { options.Select(filter.KeyFilter, filter.LabelFilter); });
    return settings;
  }
}