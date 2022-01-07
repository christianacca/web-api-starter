using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Extensions.Http;
using Microsoft.Extensions.Logging;

namespace Template.Functions;

public static class GetEcho {
  [FunctionName("Echo")]
  public static IActionResult RunAsync(
    [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = null)]
    HttpRequest req, ILogger log, ClaimsPrincipal user) {
    log.LogInformation("{FuncClass}: HTTP trigger function processed a request", nameof(GetEcho));

    log.LogInformation("{FuncClass}... user.Identity.Name: {UserName}", nameof(GetEcho), user.Identity?.Name);
    foreach (var claim in user.Claims) {
      log.LogInformation("Claim: {Claim}", claim);
    }

    var value = new { req.Host, req.Headers };
    return new OkObjectResult(value);
  }
}