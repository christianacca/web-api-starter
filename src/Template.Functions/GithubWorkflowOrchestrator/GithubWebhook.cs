using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using Microsoft.DurableTask.Client;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Microsoft.Extensions.Primitives;
using Octokit.Webhooks;
using Octokit.Webhooks.Events;
using Octokit.Webhooks.Events.WorkflowRun;
using Octokit.Webhooks.Models;
using System.Text.Json;
using Template.Shared.Github;
using Template.Shared.Proxy;

namespace Template.Functions.GithubWorkflowOrchestrator;

public class GithubWebhook(
  IOptionsMonitor<GithubAppOptions> appOptions,
  ILogger<GithubWebhook> logger) {

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

    if (!ValidateSignature(req, requestBody, out var signatureHeader)) {
      logger.LogWarning("GitHub webhook signature validation failed at Function layer. Signature: {Signature}", signatureHeader);
      return new UnauthorizedResult();
    }

    var webhookHeaders = GetWebhookHeaders(req);
    if (webhookHeaders.Event != WebhookEventType.WorkflowRun) return new AcceptedResult();

    var workflowRunEvent = JsonSerializer.Deserialize<WorkflowRunEvent>(requestBody);
    if (workflowRunEvent == null) {
      return new BadRequestObjectResult(InvalidRequestBodyMessage);
    }

    if (!IsValidRepository(workflowRunEvent)) {
      return new OkResult();
    }

    var instanceId = ExtractInstanceId(workflowRunEvent.WorkflowRun.Name);
    if (instanceId == null) {
      return new BadRequestObjectResult(InvalidWorkflowRunNameMessage);
    }

    await RaiseWorkflowEvents(instanceId, workflowRunEvent, client, cancellationToken);
    return new OkResult();
  }

  private static WebhookHeaders GetWebhookHeaders(HttpRequest req) {
    var headers = req.Headers.ToDictionary(
      kv => kv.Key,
      kv => new StringValues([.. kv.Value]),
      StringComparer.OrdinalIgnoreCase);

    var webhookHeaders = WebhookHeaders.Parse(headers);
    return webhookHeaders;
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

  private bool ValidateSignature(HttpRequest req, string requestBody, out string? signatureHeader) {
    req.Headers.TryGetValue(GithubHeaderNames.Signature256, out var headerValues);
    signatureHeader = headerValues.FirstOrDefault();

    var secret = appOptions.CurrentValue.WebhookSecret;

    return GithubWebhookSignatureValidator.IsValidSignature(requestBody, signatureHeader, secret);
  }

  private bool IsValidRepository(WorkflowRunEvent workflowEvent) {
    var expectedRepoFullName = $"{appOptions.CurrentValue.Owner}/{appOptions.CurrentValue.Repo}";
    return workflowEvent.WorkflowRun.Repository.FullName.Equals(expectedRepoFullName, StringComparison.OrdinalIgnoreCase);
  }

  private static string? ExtractInstanceId(string workflowRunName) {
    return !workflowRunName.StartsWith(WorkflowRunNamePrefix, StringComparison.OrdinalIgnoreCase)
      ? null
      : workflowRunName[WorkflowRunNamePrefix.Length..];
  }


}
