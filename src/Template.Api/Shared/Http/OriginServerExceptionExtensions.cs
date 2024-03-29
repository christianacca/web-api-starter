namespace Template.Api.Shared.Http;

public static class OriginServerExceptionExtensions {
  public static void SetOriginInfo(this Exception ex, OriginRequestInfo value) {
    ex.Data[nameof(OriginRequestInfo)] = value;
  }

  public static OriginRequestInfo? GetOriginInfo(this Exception ex) {
    Exception? currentEx = ex;
    OriginRequestInfo? value = null;
    while (value == null && currentEx != null) {
      value = currentEx.Data.Contains(nameof(OriginRequestInfo))
        ? currentEx.Data[nameof(OriginRequestInfo)] as OriginRequestInfo
        : null;
      currentEx = currentEx.InnerException;
    }

    return value;
  }
}