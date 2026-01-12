using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.DurableTask.Client;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using System.Net;
using System.Text.Json;
using System.Text.Json.Serialization;
using Template.Shared.Github;

namespace Template.Functions.GithubWorkflowOrchestrator;

public class WorkflowWebhook(
  IOptionsMonitor<GithubAppOptions> appOptions,
  ILogger<WorkflowWebhook> logger) {

  public const string WorkflowCompletedEvent = "WorkflowCompleted";
  public const string WorkflowInProgressEvent = "WorkflowInProgress";
  private const string InvalidRequestBodyMessage = "Invalid request body";
  private const string InvalidWorkflowRunNameMessage = "Workflow run name must be in format 'prefix-instanceId'";

  private static readonly JsonSerializerOptions JsonOptions = new() {
    PropertyNameCaseInsensitive = true,
    PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
    Converters = { new JsonStringEnumConverter(JsonNamingPolicy.SnakeCaseLower) }
  };

  [Function(nameof(WorkflowWebhook))]
  public async Task<HttpResponseData> RunAsync(
    [HttpTrigger(AuthorizationLevel.Anonymous, "POST", Route = "workflow/webhook")] HttpRequestData req,
    [DurableClient] DurableTaskClient client
    ) {
    var requestBody = await new StreamReader(req.Body).ReadToEndAsync();

    if (!ValidateSignature(req, requestBody, out var signatureHeader)) {
      logger.LogWarning("GitHub webhook signature validation failed at Function layer. Signature: {Signature}", signatureHeader);
      return req.CreateResponse(HttpStatusCode.Unauthorized);
    }

    var workflowEvent = JsonSerializer.Deserialize<GitHubWorkflowRunEvent>(requestBody, JsonOptions);

    if (workflowEvent == null) {
      return await CreateBadRequestResponse(req, InvalidRequestBodyMessage);
    }

    if (!IsValidRepository(workflowEvent)) {
      return req.CreateResponse(HttpStatusCode.OK);
    }

    var instanceId = ExtractInstanceId(workflowEvent.WorkflowRun.Name);
    if (instanceId == null) {
      return await CreateBadRequestResponse(req, InvalidWorkflowRunNameMessage);
    }

    await ProcessWorkflowEvent(instanceId, workflowEvent, client);

    return req.CreateResponse(HttpStatusCode.OK);
  }

  private bool ValidateSignature(HttpRequestData req, string requestBody, out string? signatureHeader) {
    req.Headers.TryGetValues(GithubHeaderNames.Signature256, out var headerValues);
    signatureHeader = headerValues?.FirstOrDefault();

    var secret = appOptions.CurrentValue.WebhookSecret;

    return GithubWebhookSignatureValidator.IsValidSignature(requestBody, signatureHeader, secret);
  }

  private bool IsValidRepository(GitHubWorkflowRunEvent workflowEvent) {
    var expectedRepoFullName = $"{appOptions.CurrentValue.Owner}/{appOptions.CurrentValue.Repo}";
    return workflowEvent.Repository.FullName.Equals(expectedRepoFullName, StringComparison.OrdinalIgnoreCase);
  }

  private string? ExtractInstanceId(string workflowRunName) {
    var parts = workflowRunName.Split('-');
    if (parts.Length != 2) {
      return null;
    }
    return parts[1];
  }

  private async Task ProcessWorkflowEvent(string instanceId, GitHubWorkflowRunEvent workflowEvent, DurableTaskClient client) {
    if (workflowEvent.Action == WorkflowRunAction.InProgress &&
        workflowEvent.WorkflowRun.Status == WorkflowRunStatus.InProgress) {
      await client.RaiseEventAsync(instanceId, WorkflowInProgressEvent, workflowEvent.WorkflowRun.Id);
    }

    if (workflowEvent.Action == WorkflowRunAction.Completed &&
        workflowEvent.WorkflowRun.Status == WorkflowRunStatus.Completed) {
      var success = workflowEvent.WorkflowRun.Conclusion == WorkflowRunConclusion.Success;
      await client.RaiseEventAsync(instanceId, WorkflowCompletedEvent, success);
    }
  }

  private static async Task<HttpResponseData> CreateBadRequestResponse(HttpRequestData req, string message) {
    var response = req.CreateResponse(HttpStatusCode.BadRequest);
    await response.WriteStringAsync(message);
    return response;
  }
}
