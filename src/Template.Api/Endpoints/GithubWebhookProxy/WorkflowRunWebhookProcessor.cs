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
  IOptionsMonitor<GithubAppOptions> appOptions) : WebhookEventProcessor {

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
    var workflowRunEvent = JsonSerializer.Deserialize<WorkflowRunEvent?>(body);
    if (workflowRunEvent == null) {
      throw new ProblemDetailsException(new StatusCodeProblemDetails(StatusCodes.Status400BadRequest) {
        Detail = "Deserialized workflow_run event is null"
      });
    }

    if (!IsValidRepository(workflowRunEvent)) {
      var repository = workflowRunEvent.WorkflowRun.Repository.FullName;
      throw new ProblemDetailsException(new StatusCodeProblemDetails(StatusCodes.Status403Forbidden) {
        Detail = $"Webhook received from invalid repository: {repository}"
      });
    }

    var workflowName = workflowRunEvent.WorkflowRun.Name;

    if (string.IsNullOrEmpty(workflowName)) {
      throw new ProblemDetailsException(new StatusCodeProblemDetails(StatusCodes.Status400BadRequest) {
        Detail = "Workflow run name is null or empty"
      });
    }

    var instanceId = ExtractInstanceId(workflowName);
    if (instanceId == null) {
      throw new ProblemDetailsException(new StatusCodeProblemDetails(StatusCodes.Status400BadRequest) {
        Detail = $"Invalid workflow run name format: {workflowName}. Expected format: '{WorkflowRunNamePrefix}instanceId'"
      });
    }

    if (workflowName.StartsWith(FunctionAppIdentifiers.InternalApi, StringComparison.OrdinalIgnoreCase)) {
      var response = await functionAppClient.Client.PostAsync(GithubWebhooksRoute,
        new StringContent(body, System.Text.Encoding.UTF8, "application/json"), cancellationToken);
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
