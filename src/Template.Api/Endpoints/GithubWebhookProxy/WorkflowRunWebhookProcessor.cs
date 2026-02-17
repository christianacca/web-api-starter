using CcAcca.ProblemDetails.Helpers;
using Hellang.Middleware.ProblemDetails;
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

  private const string DeserializeErrorMessage = "Failed to deserialize workflow_run event";
  private const string WorkflowRunEmptyMessage = "Workflow run name is null or empty";

  public override ValueTask ProcessWebhookAsync(IDictionary<string, StringValues> headers, string body, CancellationToken cancellationToken = default) {
    var webhookHeaders = WebhookHeaders.Parse(headers);
    return webhookHeaders.Event switch {
      WebhookEventType.WorkflowRun => ProcessWorkflowRunAsync(body, cancellationToken),
      _ => ValueTask.CompletedTask
    };
  }
  private async ValueTask ProcessWorkflowRunAsync(string body, CancellationToken cancellationToken) {
    var workflowRunEvent = JsonSerializer.Deserialize<WorkflowRunEvent?>(body);
    if (workflowRunEvent == null) {
      logger.LogError(DeserializeErrorMessage);
      throw new ProblemDetailsException(new StatusCodeProblemDetails(StatusCodes.Status400BadRequest) {
        Detail = DeserializeErrorMessage
      });
    }

    if (!IsValidRepository(workflowRunEvent)) {
      var repository = workflowRunEvent.WorkflowRun.Repository.FullName;
      logger.LogError("Webhook received from invalid repository: {Repository}", repository);
      throw new ProblemDetailsException(new StatusCodeProblemDetails(StatusCodes.Status403Forbidden) {
        Detail = $"Webhook received from invalid repository: {repository}"
      });
    }

    var workflowName = workflowRunEvent.WorkflowRun.Name;

    if (string.IsNullOrEmpty(workflowName)) {
      logger.LogError(WorkflowRunEmptyMessage);
      throw new ProblemDetailsException(new StatusCodeProblemDetails(StatusCodes.Status400BadRequest) {
        Detail = WorkflowRunEmptyMessage
      });
    }

    var instanceId = ExtractInstanceId(workflowName);
    if (instanceId == null) {
      logger.LogError("Invalid workflow run name format: {WorkflowName}. Expected format: '{ExpectedPrefix}instanceId'", workflowName, WorkflowRunNamePrefix);
      throw new ProblemDetailsException(new StatusCodeProblemDetails(StatusCodes.Status400BadRequest) {
        Detail = $"Invalid workflow run name format: {workflowName}. Expected format: '{WorkflowRunNamePrefix}instanceId'"
      });
    }

    if (workflowName.StartsWith(FunctionAppIdentifiers.InternalApi, StringComparison.OrdinalIgnoreCase)) {
      var response = await functionAppClient.Client.PostAsync(GithubWebhooksRoute,
        new StringContent(body, System.Text.Encoding.UTF8, "application/json"), cancellationToken);
      
      if (!response.IsSuccessStatusCode) {
        var responseBody = await response.Content.ReadAsStringAsync(cancellationToken);
        logger.LogError("Function app webhook proxy failed. StatusCode: {StatusCode}, Response: {Response}", response.StatusCode, responseBody);
      }
      
      await response.EnsureSuccessAsync(cancellationToken);
      return;
    }

    logger.LogWarning("Webhook received for unsupported workflow run: {WorkflowName}", workflowName);
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
