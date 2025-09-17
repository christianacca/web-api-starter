using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Template.Functions.Shared;
using Template.Shared.Azure.MessageQueue;

namespace Template.Functions;

public class GetEcho(ILogger<GetEcho> logger) {
  [Function("Echo")]
  public IActionResult Run([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = null)] HttpRequest req) {
    logger.LogInformation("{FuncClass}: HTTP trigger function processed a request", nameof(GetEcho));

    var user = req.HttpContext.User;
    logger.LogInformation("{FuncClass}... user.Identity.Name: {UserName}", nameof(GetEcho), user.Identity?.Name);
    foreach (var claim in user.Claims) {
      logger.LogInformation("Identity Claim... {ClaimType}:{ClaimValue}", claim.Type, claim.Value);
    }

    var sanitizedHeaders =
      req.Headers.SanitizeJwtTokenAuthzHeader(additional: TokenValidatorExtensions.MriOriginalAuthorizationHeader);

    foreach (var header in sanitizedHeaders) {
      logger.LogInformation("Header... {HeaderName}:{HeaderValue}", header.Key, header.Value.ToString());
    }

    var value = new { req.Host, Headers = sanitizedHeaders, Claims = user.Claims.Select(ClaimDto.From) };
    return new OkObjectResult(value);
  }
}