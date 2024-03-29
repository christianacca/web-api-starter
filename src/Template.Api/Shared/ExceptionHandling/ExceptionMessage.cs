namespace Template.Api.Shared.ExceptionHandling; 

public static class ExceptionMessage {
  /// <summary>
  /// Mark an exception as having a message that is safe to return to the consumer
  /// </summary>
  /// <example>
  /// <code lang="c#">
  /// throw new InvalidOperationException(
  ///   "Some message that is safe to return that could be displayed to the user even") {
  ///   Data = { { ExceptionMessage.MarkAsSafeMessage, true } }
  /// }
  /// </code>
  /// </example>
  public const string MarkAsSafeMessage = "SafeMessage";

  /// <summary>
  /// Returns the value of <see cref="Exception.Message"/> from the supplied <paramref name="ex"/> but
  /// only when <paramref name="ex"/> has been marked as having a message text that is safe
  /// </summary>
  /// <seealso cref="ExceptionMessage.MarkAsSafeMessage"/>
  public static string? GetSafeExceptionMessage(this Exception ex) {
    return ex.Data.Contains(MarkAsSafeMessage) && true.Equals(ex.Data[MarkAsSafeMessage]) ? ex.Message : null;
  }
}