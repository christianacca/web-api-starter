namespace Template.Api.Shared.Proxy;

public class FunctionAppHttpClient {
  public HttpClient Client { get; }

  public FunctionAppHttpClient(HttpClient client) {
    Client = client;
  }
}