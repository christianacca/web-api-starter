namespace Template.Api.Shared.Proxy;

public class FunctionAppHttpClient(HttpClient client) {
  public HttpClient Client { get; } = client;
}