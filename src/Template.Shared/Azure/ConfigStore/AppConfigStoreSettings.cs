using Azure.Identity;
using Microsoft.Extensions.Configuration.AzureAppConfiguration;
using Microsoft.Extensions.Configuration.AzureAppConfiguration.Models;

namespace Template.Shared.Azure.ConfigStore;

public class AppConfigStoreSettings {
  private static readonly Uri PlaceholderUri = new("https://does-not-exist.azconfig.io");

  public class RefreshOptions {
    /// <summary>
    /// List of keys to refresh on each refresh interval
    /// </summary>
    public ICollection<string> Keys { get; set; } = new HashSet<string>();

    /// <summary>
    /// Controls how the config store is refreshed. Defaults to <see cref="AppConfigStoreRefreshStrategy.SentinelKey"/>
    /// </summary>
    public AppConfigStoreRefreshStrategy Strategy { get; set; } = AppConfigStoreRefreshStrategy.SentinelKey;

    /// <summary>
    /// The interval at which the config store is refreshed. The default is 30 seconds
    /// </summary>
    public TimeSpan RefreshInterval { get; set; } = TimeSpan.FromSeconds(30);

    /// <summary>
    /// The key to monitor for changes to trigger a refresh of all keys
    /// </summary>
    public string SentinelKey { get; set; } = "SentinelKey";
  }

  public class FeatureOptions {
    public bool Enabled { get; set; }

    /// <summary>
    /// The interval at which feature flags will be refreshed. The default is 30 seconds
    /// </summary>
    public TimeSpan RefreshInterval { get; set; } = TimeSpan.FromSeconds(30);

    /// <summary>
    /// Filter the feature flags to load based so that only keys belonging to specific sections are loaded
    /// </summary>
    /// <remarks>
    /// Leave this empty to load all feature flags
    /// </remarks>
    public ICollection<string> Sections { get; set; } = new HashSet<string>();
  }


  public bool ConfigStoreDisabled { get; set; }

  /// <summary>
  /// The label filter to identity environment specific key values to load from the config store.
  /// If not set, only keys with no label will be loaded
  /// </summary>
  public string? ConfigStoreEnvironmentLabelFilter { get; set; }

  public FeatureOptions ConfigStoreFeatureFlags { get; } = new();
  public RefreshOptions ConfigStoreRefresh { get; } = new();
  public bool ConfigStoreReplicaDiscoveryEnabled { get; set; }

  /// <summary>
  /// Filter the keys to load based so that only keys belonging to specific configuration sections are loaded
  /// </summary>
  /// <remarks>
  /// Leave this empty to load all keys
  /// </remarks>
  public ICollection<string> ConfigStoreSections { get; set; } = new HashSet<string>();

  /// <summary>
  /// The URI of the Azure config store
  /// </summary>
  public Uri ConfigStoreUri { get; set; } = PlaceholderUri;

  /// <summary>
  /// The options determining the authentication used to authenticate to Azure config store
  /// </summary>
  public DefaultAzureCredentialOptions DefaultAzureCredentials { get; set; } = new();

  /// <summary>
  /// Should config store be added as a source of configuration. Defaults to <c>true</c> when a <see cref="ConfigStoreUri"/> has been supplied
  /// </summary>
  public bool IsEnabled => !ConfigStoreDisabled && ConfigStoreUri != PlaceholderUri;

  /// <summary>
  /// Returns a list of <see cref="KeyValueSelector"/> objects that will match keys listed in
  /// <see cref="RefreshOptions.Keys"/> that require refreshing. The resulting selectors will select all
  /// those keys that do not have a label applied, have a label matching <see cref="ConfigStoreEnvironmentLabelFilter"/>
  /// when set, or have a label with a prefix derived from <see cref="ConfigStoreEnvironmentLabelFilter"/>
  /// (eg prod-na becomes prod).
  /// </summary>
  public IEnumerable<KeyValueSelector> KeysToRefreshSelectors => GetKeySelectors(ConfigStoreRefresh.Keys);


  /// <summary>
  /// Returns a list of <see cref="KeyValueSelector"/> objects that will match keys belonging to config sections
  /// listed in <see cref="ConfigStoreSections"/> or defaulting to all keys. The resulting selectors will select all
  /// those keys that do not have a label applied, have a label matching <see cref="ConfigStoreEnvironmentLabelFilter"/>
  /// when set, or have a label with a prefix derived from <see cref="ConfigStoreEnvironmentLabelFilter"/>
  /// (eg prod-na becomes prod).
  /// </summary>
  public IEnumerable<KeyValueSelector> KeySelectors => GetKeySectionSelectors(ConfigStoreSections);

  /// <summary>
  /// Returns a list of <see cref="KeyValueSelector"/> objects that will match feature flags belonging to sections
  /// listed in <see cref="FeatureOptions.Sections"/> or defaulting to all flags. The resulting selectors will
  /// select all those flags that do not have a label applied, have a label matching
  /// <see cref="ConfigStoreEnvironmentLabelFilter"/> when set, or have a label with a prefix derived from
  /// <see cref="ConfigStoreEnvironmentLabelFilter"/> (eg prod-na becomes prod).
  /// </summary>
  public IEnumerable<KeyValueSelector> FeatureFlagSelectors => GetKeySectionSelectors(ConfigStoreFeatureFlags.Sections);

  /// <summary>
  /// A selector that matches the sentinel key used to trigger a refresh of all keys when <see cref="AppConfigStoreRefreshStrategy"/>
  /// is set to <see cref="AppConfigStoreRefreshStrategy.SentinelKey"/>
  /// </summary>
  /// <remarks>
  /// If set, a key with a label matching <see cref="ConfigStoreEnvironmentLabelFilter"/> will be monitored, otherwise
  /// a key with no label will be monitored.
  /// </remarks>
  public KeyValueSelector SentinelKeySelector {
    get {
      var labelFilter = string.IsNullOrWhiteSpace(ConfigStoreEnvironmentLabelFilter)
        ? LabelFilter.Null
        : ConfigStoreEnvironmentLabelFilter;
      return new KeyValueSelector { KeyFilter = ConfigStoreRefresh.SentinelKey, LabelFilter = labelFilter };
    }
  }

  private string? EnvironmentLabelPrefixFilter {
    get {
      if (string.IsNullOrWhiteSpace(ConfigStoreEnvironmentLabelFilter)) {
        return null;
      }

      var labelParts = ConfigStoreEnvironmentLabelFilter.Split('-');
      return labelParts.Length > 1 ? labelParts[0] : null;
    }
  }

  private IEnumerable<KeyValueSelector> GetKeySectionSelectors(ICollection<string> sections) {
    IEnumerable<string> keyFilters = sections.Count == 0
      ? [KeyFilter.Any]
      : sections.Select(section => $"{section}:*");
    return GetKeySelectors(keyFilters);
  }

  private IEnumerable<KeyValueSelector> GetKeySelectors(IEnumerable<string> keyFilters) {
    var hasLabelFilter = !string.IsNullOrWhiteSpace(ConfigStoreEnvironmentLabelFilter);
    var labelPrefix = EnvironmentLabelPrefixFilter;
    foreach (var keyFilter in keyFilters) {
      yield return new KeyValueSelector { KeyFilter = keyFilter, LabelFilter = LabelFilter.Null };
      if (labelPrefix != null) {
        yield return new KeyValueSelector { KeyFilter = keyFilter, LabelFilter = labelPrefix };
      }

      if (hasLabelFilter) {
        yield return new KeyValueSelector { KeyFilter = keyFilter, LabelFilter = ConfigStoreEnvironmentLabelFilter };
      }
    }
  }
}