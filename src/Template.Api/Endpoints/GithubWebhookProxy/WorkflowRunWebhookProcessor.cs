using CcAcca.ProblemDetails.Helpers;
using Microsoft.Extensions.Options;
using Microsoft.Extensions.Primitives;
using Octokit.Webhooks;
using Octokit.Webhooks.Events;
using System.Text.Json;
using Template.Api.Shared.Proxy;
using Template.Shared.Github;
using Template.Shared.Proxy;

namespace Template.Api.Endpoints.GithubWebhookProxy;

public class WorkflowRunWebhookProcessor(
  FunctionAppHttpClient functionAppClient,
  IOptionsMonitor<GithubAppOptions> appOptions,
  ILogger<WorkflowRunWebhookProcessor> logger) : WebhookEventProcessor {

  private static readonly string GithubWebhooksRoute = "api/github/webhooks";
  private static readonly string WorkflowRunNamePrefix = $"{FunctionAppIdentifiers.InternalApi}-";

  public override ValueTask ProcessWebhookAsync(IDictionary<string, StringValues> headers, string body, CancellationToken cancellationToken = default) {
    var webhookHeaders = WebhookHeaders.Parse(headers);
    return webhookHeaders.Event switch {
      WebhookEventType.WorkflowRun => ProcessWorkflowRunAsync(body, cancellationToken),
      _ => ValueTask.CompletedTask
    };
  }
  private async ValueTask ProcessWorkflowRunAsync(string body, CancellationToken cancellationToken) {
    WorkflowRunEvent? workflowRunEvent;
    try {
      workflowRunEvent = JsonSerializer.Deserialize<WorkflowRunEvent>(body);
      if (workflowRunEvent == null) {
        return;
      }
    }
    catch (JsonException ex) {
      logger.LogError(ex, "Error deserializing workflow_run webhook payload");
      return;
    }

    if (!IsValidRepository(workflowRunEvent)) {
      logger.LogWarning("Webhook received from invalid repository: {Repository}", workflowRunEvent.WorkflowRun.Repository.FullName);
      return;
    }

    var workflowName = workflowRunEvent.WorkflowRun.Name;

    if (string.IsNullOrEmpty(workflowName)) {
      logger.LogWarning("Workflow run name is null or empty");
      return;
    }

    var instanceId = ExtractInstanceId(workflowName);
    if (instanceId == null) {
      logger.LogWarning("Invalid workflow run name format: {WorkflowName}. Expected format: '{Prefix}instanceId'", workflowName, WorkflowRunNamePrefix);
      return;
    }

    if (workflowName.StartsWith(FunctionAppIdentifiers.InternalApi, StringComparison.OrdinalIgnoreCase)) {
      var response = await functionAppClient.Client.PostAsync(GithubWebhooksRoute, new StringContent(body), cancellationToken);
      await response.EnsureNotProblemDetailAsync(cancellationToken);
    }
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
