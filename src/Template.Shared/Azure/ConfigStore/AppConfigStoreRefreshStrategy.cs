namespace Template.Shared.Azure.ConfigStore;

public enum AppConfigStoreRefreshStrategy {
  /// <summary>
  /// Do not refresh keys on an interval
  /// </summary>
  None,

  /// <summary>
  /// Refresh all keys on each refresh interval
  /// </summary>
  RefreshAll,

  /// <summary>
  /// Monitor a sentinel key on each refresh interval, to trigger a refresh of all key values
  /// </summary>
  SentinelKey,

  /// <summary>
  /// Refresh only the keys on each refresh interval
  /// </summary>
  SpecificKeys
}