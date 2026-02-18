using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Template.Functions.Shared;

namespace Template.Functions;

public class GetUser {
  private class GetUserRequest {
    public string? Name { get; set; }
  }

  private ITokenValidator TokenValidator { get; }
  private ILogger<GetUser> Logger { get; }

  public GetUser(ITokenValidator tokenValidator, ILogger<GetUser> logger) {
    TokenValidator = tokenValidator;
    Logger = logger;
  }

  [Function("User")]
  public async Task<IActionResult> Run(
    [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = null)]
    HttpRequest req,
    CancellationToken cancellationToken = default) {
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

    if (string.IsNullOrWhiteSpace(name) && req.ContentLength > 0) {
      var modelResult = await req.TryReadFromJsonAsync<GetUserRequest>(cancellationToken);
      if (modelResult.IsSuccess) {
        name = modelResult.Value.Name;
      }
    }
    
    name ??= "";

    var userDto = new { Id = user.Identity?.Name, Name = name };

    return !string.IsNullOrWhiteSpace(name)
      ? new OkObjectResult(userDto)
      : new BadRequestObjectResult("Please pass a name on the query string or in the request body");
  }
}