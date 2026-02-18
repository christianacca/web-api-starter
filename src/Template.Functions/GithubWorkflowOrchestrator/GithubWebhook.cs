using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using Microsoft.DurableTask.Client;
using Microsoft.Extensions.Logging;
using Octokit.Webhooks.Events;
using Octokit.Webhooks.Events.WorkflowRun;
using Octokit.Webhooks.Models;
using Template.Shared.Github;
using Template.Shared.Proxy;

namespace Template.Functions.GithubWorkflowOrchestrator;

public class GithubWebhook(ILogger<GithubWebhook> logger) {
  public const string WorkflowCompletedEvent = "WorkflowCompleted";
  public const string WorkflowInProgressEvent = "WorkflowInProgress";

  private const string RequestBodyNullMessage = "Request body is null";
  private const string InvalidWorkflowRunNameMessage = "Workflow run name must be in format 'WorkflowRunNamePrefix-instanceId'";

  private static readonly string WorkflowRunNamePrefix = $"{FunctionAppIdentifiers.InternalApi}-";

  [Function(nameof(GithubWebhook))]
  public async Task<IActionResult> RunAsync(
    [HttpTrigger(AuthorizationLevel.Anonymous, "POST", Route = "github/webhooks")] HttpRequest req,
    [DurableClient] DurableTaskClient client,
    CancellationToken cancellationToken = default) {

    var requestBody = await new StreamReader(req.Body).ReadToEndAsync(cancellationToken);

    WorkflowRunEvent? workflowRunEvent;
    try {
      workflowRunEvent = JsonSerializer.Deserialize<WorkflowRunEvent>(requestBody);
    } catch (Exception ex) {
      logger.LogError(ex, "Failed to deserialize webhook request body");
      throw;
    }
    if (workflowRunEvent == null) {
      logger.LogWarning(RequestBodyNullMessage);
      return new BadRequestObjectResult(RequestBodyNullMessage);
    }

    var instanceId = WorkflowRunHelper.ExtractInstanceId(workflowRunEvent.WorkflowRun.Name, WorkflowRunNamePrefix);
    if (instanceId == null) {
      logger.LogWarning("Failed to extract instance ID from workflow run name: {WorkflowRunName}", workflowRunEvent.WorkflowRun.Name);
      return new BadRequestObjectResult(InvalidWorkflowRunNameMessage);
    }

    await RaiseWorkflowEvents(instanceId, workflowRunEvent, client, cancellationToken);
    return new OkResult();
  }

  private async Task RaiseWorkflowEvents(string instanceId, WorkflowRunEvent workflowEvent, DurableTaskClient client, CancellationToken ct) {
    if (workflowEvent.Action == WorkflowRunAction.InProgress && workflowEvent.WorkflowRun.Status == WorkflowRunStatus.InProgress) {
      await client.RaiseEventAsync(instanceId, WorkflowInProgressEvent, workflowEvent.WorkflowRun.Id, ct);
      return;
    }

    if (workflowEvent.Action == WorkflowRunAction.Completed &&
        workflowEvent.WorkflowRun.Status == WorkflowRunStatus.Completed) {
      var success = workflowEvent.WorkflowRun.Conclusion.HasValue &&
                    workflowEvent.WorkflowRun.Conclusion.Value == WorkflowRunConclusion.Success;
      await client.RaiseEventAsync(instanceId, WorkflowCompletedEvent, success, ct);
      return;
    }

    logger.LogWarning("Received workflow event with unmapped action/status combination. Action: {Action}, Status: {Status}",
      workflowEvent.Action, workflowEvent.WorkflowRun.Status);
  }
}
