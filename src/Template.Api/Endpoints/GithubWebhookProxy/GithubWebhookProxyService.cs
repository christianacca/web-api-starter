using Template.Api.Shared.Proxy;
using Template.Shared.Proxy;

namespace Template.Api.Endpoints.GithubWebhookProxy;

public class GithubWebhookProxyService(FunctionAppHttpClient functionAppClient) {

  public async Task<HttpResponseMessage> ForwardWebhookAsync(HttpRequest originalRequest, string requestBody,
    string functionAppIdentifier, CancellationToken ct) {

    var forwardRequest = new HttpRequestMessage(HttpMethod.Post, "api/workflow/webhook") {
      Content = new StringContent(requestBody, System.Text.Encoding.UTF8, "application/json")
    };

    foreach (var header in originalRequest.Headers) {
      if (ShouldForwardHeader(header.Key)) {
        forwardRequest.Headers.TryAddWithoutValidation(header.Key, header.Value.ToArray());
      }
    }

    switch (functionAppIdentifier) {
      case FunctionAppIdentifiers.InternalApi:
        return await functionAppClient.Client.SendAsync(forwardRequest, ct);
    }

    return new HttpResponseMessage();
  }

  private static bool ShouldForwardHeader(string headerName) {
    // Don't forward headers that are automatically set by HttpClient
    var headersToSkip = new[] {
      "Host",
      "Connection",
      "Content-Length",
      "Transfer-Encoding"
    };

    return !headersToSkip.Contains(headerName, StringComparer.OrdinalIgnoreCase);
  }
}
