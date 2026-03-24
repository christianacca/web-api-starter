using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

namespace Template.Functions.GithubWorkflowOrchestrator;

public class GithubWebhook(ILogger<GithubWebhook> logger) {
  [Function(nameof(GithubWebhook))]
  public async Task<IActionResult> RunAsync(
    [HttpTrigger(AuthorizationLevel.Anonymous, "POST", Route = "github/webhooks")] HttpRequest req,
    CancellationToken cancellationToken = default) {
    await req.BodyReader.CompleteAsync();

    logger.LogWarning("Github workflow webhook endpoint is disabled. Queue-driven workflow event delivery is now owned by ExampleQueue.");
    return new StatusCodeResult(StatusCodes.Status410Gone);
  }
}
