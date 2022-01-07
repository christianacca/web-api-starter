namespace Template.Api.Shared.Proxy;

public class HeaderForwardingHttpClientHandler : DelegatingHandler {
  private IHttpContextAccessor HttpContextAccessor { get; }

  public HeaderForwardingHttpClientHandler(IHttpContextAccessor httpContextAccessor) {
    HttpContextAccessor = httpContextAccessor;
  }

  protected override async Task<HttpResponseMessage> SendAsync(
    HttpRequestMessage request, CancellationToken cancellationToken) {
    var httpContext = HttpContextAccessor.HttpContext;
    if (httpContext != null) {
      var originalAuthHeader = httpContext.Request.Headers.Authorization.ToString();
      if (!string.IsNullOrEmpty(originalAuthHeader)) {
        request.Headers.Add(HeaderNames.OriginalAuthorization, originalAuthHeader);
      }

      var remoteIp = httpContext.Connection.RemoteIpAddress?.ToString();
      if (!string.IsNullOrEmpty(remoteIp)) {
        request.Headers.Add("X-Forwarded-For", remoteIp);
      }

      var host = httpContext.Request.Host;
      if (host.HasValue) {
        request.Headers.Add("X-Forwarded-Host", host.ToUriComponent());
      }

      var scheme = httpContext.Request.Scheme;
      if (!string.IsNullOrEmpty(scheme)) {
        request.Headers.Add("X-Forwarded-Proto", scheme);
      }
    }

    return await base.SendAsync(request, cancellationToken);
  }
}