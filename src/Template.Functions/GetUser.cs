using System.IO;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Extensions.Http;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json;
using Template.Functions.Shared;

namespace Template.Functions;

public class GetUser {
  private ITokenValidator TokenValidator { get; }

  public GetUser(ITokenValidator tokenValidator) {
    TokenValidator = tokenValidator;
  }

  [FunctionName("User")]
  public async Task<IActionResult> Run(
    [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = null)]
    HttpRequest req, ILogger log) {
    log.LogInformation("{FuncClass}... HTTP trigger function processed a request", nameof(GetUser));

    var user = await TokenValidator.ValidateBearerTokenAsync(req.Headers);
    if (user == null) {
      return new UnauthorizedResult();
    }

    log.LogInformation("{FuncClass}... user.Identity.Name: {UserName}", nameof(GetUser), user.Identity?.Name);
    foreach (var claim in user.Claims) {
      log.LogInformation("Claim: {Claim}", claim);
    }

    string name = req.Query["name"];

    string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
    dynamic data = JsonConvert.DeserializeObject(requestBody);
    name ??= data?.name ?? "";

    var userDto = new { Id = user.Identity?.Name, Name = name };

    return string.IsNullOrWhiteSpace(name)
      ? new OkObjectResult(userDto)
      : new BadRequestObjectResult("Please pass a name on the query string or in the request body");
  }
}