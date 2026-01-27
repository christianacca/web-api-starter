using Microsoft.DurableTask;

namespace Template.Functions.Shared;

public static class DurableContextExtensions {
  /// <summary>
  /// Waits for an external event with a timeout. Returns the default value if the timeout occurs.
  /// </summary>
  /// <typeparam name="T">The type of the event payload</typeparam>
  /// <param name="context">The orchestration context</param>
  /// <param name="eventName">The name of the external event to wait for</param>
  /// <param name="timeout">The maximum time to wait for the event</param>
  /// <param name="defaultValue">The value to return if the timeout occurs</param>
  /// <returns>The event payload if received, or the default value if timeout occurs</returns>
  public static async Task<T> WaitForExternalEvent<T>(
      this TaskOrchestrationContext context,
      string eventName,
      TimeSpan timeout,
      T defaultValue) {
    try {
      return await context.WaitForExternalEvent<T>(eventName, timeout);
    }
    catch (TaskCanceledException) {
      return defaultValue;
    }
  }
}
