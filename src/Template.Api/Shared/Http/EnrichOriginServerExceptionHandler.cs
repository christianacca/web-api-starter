namespace Template.Api.Shared.Http;

/// <summary>
/// Enrich exceptions thrown when sending a http request with details that can be used to create a an
/// appropriate problem-details response.
/// </summary>
internal class EnrichOriginServerExceptionHandler : DelegatingHandler {
  private string? OriginServiceName { get; }

  public EnrichOriginServerExceptionHandler(string? originServiceName) {
    OriginServiceName = originServiceName;
  }

  protected override async Task<HttpResponseMessage> SendAsync(
    HttpRequestMessage request, CancellationToken cancellationToken
  ) {
    try {
      return await base.SendAsync(request, cancellationToken);
    }
    catch (Exception ex) {
      // mutating the exception so as preserve the original exception stack trace
      ex.SetOriginInfo(new OriginRequestInfo {
        OriginRequestUri = request.RequestUri ?? OriginRequestInfo.UnknownRequestUri,
        OriginServiceName = OriginServiceName
      });
      throw;
    }
  }
}