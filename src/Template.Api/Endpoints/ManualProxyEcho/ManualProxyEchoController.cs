using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Template.Api.Shared.Proxy;

namespace Template.Api.Endpoints.ManualProxyEcho;

[Route("api/[controller]")]
[ApiController]
public class ManualProxyEchoController : ControllerBase {
  private HttpClient HttpClient { get; }

  public ManualProxyEchoController(FunctionAppHttpClient httpClient) {
    HttpClient = httpClient.Client;
  }

  [AllowAnonymous]
  [HttpGet]
  public async Task<JsonElement> Get() {
    return await HttpClient.GetFromJsonAsync<JsonElement>("api/echo");
  }
}