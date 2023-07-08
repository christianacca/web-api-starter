using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

namespace Template.Functions;

public class GetEcho {
  private ILogger<GetEcho> Logger { get; }

  public GetEcho(ILogger<GetEcho> logger) {
    Logger = logger;
  }

  [Function("Echo")]
  public IActionResult Run([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = null)] HttpRequest req) {
    Logger.LogInformation("{FuncClass}: HTTP trigger function processed a request", nameof(GetEcho));

    var user = req.HttpContext.User;
    Logger.LogInformation("{FuncClass}... user.Identity.Name: {UserName}", nameof(GetEcho), user.Identity?.Name);
    foreach (var claim in user.Claims) {
      Logger.LogInformation("Claim: {Claim}", claim);
    }

    var value = new { req.Host, req.Headers };
    return new OkObjectResult(value);
  }
}