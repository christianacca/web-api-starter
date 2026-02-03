using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Primitives;
using Octokit.Webhooks;
using Octokit.Webhooks.Events;
using Template.Api.Shared.Proxy;
using Template.Shared.Github;
using Template.Shared.Proxy;

namespace Template.Api.Endpoints.GithubWebhookProxy;

public class WorkflowRunWebhookProcessor(
  FunctionAppHttpClient functionAppClient,
  ILogger<WorkflowRunWebhookProcessor> logger) : WebhookEventProcessor {

  public override ValueTask ProcessWebhookAsync(IDictionary<string, StringValues> headers, string body, CancellationToken cancellationToken = default) {
    var webhookHeaders = WebhookHeaders.Parse(headers);
    return webhookHeaders.Event switch {
      WebhookEventType.WorkflowRun => ProcessWorkflowRunAsync(headers, body, cancellationToken),
      _ => ValueTask.CompletedTask
    };
  }

  private async ValueTask ProcessWorkflowRunAsync(IDictionary<string, StringValues> headers, string body, CancellationToken cancellationToken) {
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

    var workflowName = workflowRunEvent.WorkflowRun.Name;

    if (string.IsNullOrEmpty(workflowName)) {
      return;
    }

    await ForwardToFunctionAppAsync(body, headers, workflowName, cancellationToken);
  }

  private async Task ForwardToFunctionAppAsync(string rawBody, IDictionary<string, StringValues> headers, string workflowName, CancellationToken ct) {
    var request = new HttpRequestMessage(HttpMethod.Post, "api/github/webhooks") {
      Content = new StringContent(rawBody, Encoding.UTF8, "application/json"),
    };

    foreach (var header in headers) {
      request.Headers.TryAddWithoutValidation(header.Key, header.Value.ToArray());
    }

    request.Headers.Add(GithubHeaderNames.WorkflowIdentifier, workflowName);

    if (workflowName.StartsWith(FunctionAppIdentifiers.InternalApi, StringComparison.OrdinalIgnoreCase)) {
      var response = await functionAppClient.Client.SendAsync(request, ct);
      response.EnsureSuccessStatusCode();
    }
  }
}
