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
  /// <param name="cancellationToken">The cancellation token to observe during the wait operation</param>
  /// <returns>The event payload if received, or the default value if timeout occurs</returns>
  public static async Task<T> WaitForExternalEvent<T>(
      this TaskOrchestrationContext context,
      string eventName,
      TimeSpan timeout,
      T defaultValue,
      CancellationToken cancellationToken = default) {
    using CancellationTokenSource eventCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
    var eventTask = context.WaitForExternalEvent<T>(eventName, eventCts.Token);

    using CancellationTokenSource timerCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
    var timerTask = context.CreateTimer(context.CurrentUtcDateTime.Add(timeout), timerCts.Token);

    var winner = await Task.WhenAny(eventTask, timerTask);

    if (winner == eventTask) {
      await timerCts.CancelAsync();
      return eventTask.Result;
    }

    await eventCts.CancelAsync();

    return defaultValue;
  }
}
