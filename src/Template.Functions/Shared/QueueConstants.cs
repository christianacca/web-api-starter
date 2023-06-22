namespace Template.Functions.Shared; 

public static class QueueConstants {
  /// <summary>
  /// The number of retries for a given queue message, including the first try
  /// </summary>
  /// <remarks>
  /// This value is actually controlled in host.json and defaults to 5 when not set. Please ensure this const value
  /// stays in-sync with the value assigned in host.json
  /// </remarks>
  public const int MaxDequeueCount = 5;
}