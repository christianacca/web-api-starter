using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using Microsoft.DurableTask.Client;
using Octokit.Webhooks.Events;
using Octokit.Webhooks.Events.WorkflowRun;
using Octokit.Webhooks.Models;
using Template.Shared.Proxy;

namespace Template.Functions.GithubWorkflowOrchestrator;

public class GithubWebhook {

  public const string WorkflowCompletedEvent = "WorkflowCompleted";
  public const string WorkflowInProgressEvent = "WorkflowInProgress";

  private const string InvalidRequestBodyMessage = "Invalid request body";
  private const string InvalidWorkflowRunNameMessage = "Workflow run name must be in format 'WorkflowRunNamePrefix-instanceId'";

  private static readonly string WorkflowRunNamePrefix = $"{FunctionAppIdentifiers.InternalApi}-";

  [Function(nameof(GithubWebhook))]
  public async Task<IActionResult> RunAsync(
    [HttpTrigger(AuthorizationLevel.Anonymous, "POST", Route = "github/webhooks")] HttpRequest req,
    [DurableClient] DurableTaskClient client,
    CancellationToken cancellationToken = default) {

    var requestBody = await new StreamReader(req.Body).ReadToEndAsync(cancellationToken);

    var workflowRunEvent = JsonSerializer.Deserialize<WorkflowRunEvent>(requestBody);
    if (workflowRunEvent == null) {
      return new BadRequestObjectResult(InvalidRequestBodyMessage);
    }

    var instanceId = ExtractInstanceId(workflowRunEvent.WorkflowRun.Name);
    if (instanceId == null) {
      return new BadRequestObjectResult(InvalidWorkflowRunNameMessage);
    }

    await RaiseWorkflowEvents(instanceId, workflowRunEvent, client, cancellationToken);
    return new OkResult();
  }

  private async Task RaiseWorkflowEvents(string instanceId, WorkflowRunEvent workflowEvent, DurableTaskClient client, CancellationToken ct) {
    if (workflowEvent.Action == WorkflowRunAction.InProgress &&
        workflowEvent.WorkflowRun.Status == WorkflowRunStatus.InProgress) {
      await client.RaiseEventAsync(instanceId, WorkflowInProgressEvent, workflowEvent.WorkflowRun.Id, ct);
    }

    if (workflowEvent.Action == WorkflowRunAction.Completed &&
        workflowEvent.WorkflowRun.Status == WorkflowRunStatus.Completed) {
      var success = workflowEvent.WorkflowRun.Conclusion.HasValue &&
                    workflowEvent.WorkflowRun.Conclusion.Value == WorkflowRunConclusion.Success;
      await client.RaiseEventAsync(instanceId, WorkflowCompletedEvent, success, ct);
    }
  }

  private static string? ExtractInstanceId(string workflowRunName) {
    return !workflowRunName.StartsWith(WorkflowRunNamePrefix, StringComparison.OrdinalIgnoreCase)
      ? null
      : workflowRunName[WorkflowRunNamePrefix.Length..];
  }
}
