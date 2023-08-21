using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Template.Functions.Shared;

namespace Template.Functions;

public class GetUser {
  private ITokenValidator TokenValidator { get; }
  private ILogger<GetUser> Logger { get; }

  public GetUser(ITokenValidator tokenValidator, ILogger<GetUser> logger) {
    TokenValidator = tokenValidator;
    Logger = logger;
  }

  [Function("User")]
  public async Task<IActionResult> Run(
    [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = null)]
    HttpRequest req) {
    Logger.LogInformation("{FuncClass}... HTTP trigger function processed a request", nameof(GetUser));

    var user = await TokenValidator.ValidateBearerTokenAsync(req.Headers);
    if (user == null) {
      return new UnauthorizedResult();
    }

    Logger.LogInformation("{FuncClass}... user.Identity.Name: {UserName}", nameof(GetUser), user.Identity?.Name);
    foreach (var claim in user.Claims) {
      Logger.LogInformation("Claim: {Claim}", claim);
    }

    string? name = req.Query["name"];

    string requestBody = await new StreamReader(req.Body).ReadToEndAsync();

    dynamic? data = string.IsNullOrWhiteSpace(requestBody) ? null : JsonSerializer.Deserialize<dynamic>(requestBody);
    name ??= data?.name ?? "";

    var userDto = new { Id = user.Identity?.Name, Name = name };

    return !string.IsNullOrWhiteSpace(name)
      ? new OkObjectResult(userDto)
      : new BadRequestObjectResult("Please pass a name on the query string or in the request body");
  }
}