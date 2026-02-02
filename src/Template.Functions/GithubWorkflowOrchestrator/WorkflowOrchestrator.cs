using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.DurableTask;
using Microsoft.DurableTask.Client;
using Microsoft.Extensions.Options;
using System.Net;
using Microsoft.Extensions.Logging;
using Template.Shared.Github;
using Template.Functions.Shared;

namespace Template.Functions.GithubWorkflowOrchestrator;

public class WorkflowOrchestrator(IOptionsMonitor<GithubAppOptions> optionsMonitor) {

  [Function(nameof(StartWorkflow))]
  public async Task<HttpResponseData> StartWorkflow(
    [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "workflow/start")] HttpRequestData req,
    [DurableClient] DurableTaskClient client,
    [FromBody] StartWorkflowRequest request) {

    var options = optionsMonitor.CurrentValue;
    var input = new OrchestratorInput {
      MaxAttempts = options.MaxAttempts,
      Timeout = options.WorkflowTimeout,
      RerunEntireWorkflow = options.RerunEntireWorkflow,
      WorkflowFile = request.WorkflowFile
    };

    var instanceId = await client.ScheduleNewOrchestrationInstanceAsync(nameof(WorkflowOrchestrator), input);

    var response = req.CreateResponse(HttpStatusCode.OK);
    await response.WriteAsJsonAsync(new {
      Id = instanceId,
    });

    return response;
  }

  private static async Task<bool> CheckWorkflowSuccessAsync(TaskOrchestrationContext context, bool? success, long runId, int currentAttempt, int maxAttempts) {
    if (success.HasValue) {
      return success.Value;
    }

    var logger = context.CreateReplaySafeLogger<WorkflowOrchestrator>();
    logger.LogWarning("Workflow completion event timed out on attempt {CurrentAttempt} of {MaxAttempts}",
        currentAttempt, maxAttempts);

    var workflowStatus = await context.CallActivityAsync<WorkflowRunInfo?>(nameof(GetWorkflowRunStatusActivity), runId);
    if (workflowStatus is not { Status: WorkflowRunStatus.Completed }) {
      return true;
    }

    return workflowStatus.Conclusion == WorkflowRunConclusion.Success;
  }

  private async Task<long?> CheckWorkflowInProgressAsync(TaskOrchestrationContext context, string workflowName) {
    var logger = context.CreateReplaySafeLogger<WorkflowOrchestrator>();
    logger.LogWarning("Workflow in-progress event timed out for workflow {WorkflowName}", workflowName);

    var runId = await context.CallActivityAsync<long?>(nameof(GetRecentWorkflowRunActivity), workflowName);

    if (runId.HasValue) {
      logger.LogInformation("Found workflow run {RunId} for workflow {WorkflowName}", runId.Value, workflowName);
    } else {
      logger.LogWarning("No workflow run found for workflow {WorkflowName}", workflowName);
    }

    return runId;
  }

  [Function(nameof(WorkflowOrchestrator))]
  public async Task RunAsync(
    [OrchestrationTrigger] TaskOrchestrationContext context) {
    var input = context.GetInput<OrchestratorInput>();
    if (input == null) return;

    var triggerInput = new TriggerInput {
      InstanceId = context.InstanceId,
      WorkflowFile = input.WorkflowFile
    };
    var workflowName = await context.CallActivityAsync<string>(nameof(TriggerWorkflowActivity), triggerInput);
    var runId = await context.WaitForExternalEvent<long>(WorkflowWebhook.WorkflowInProgressEvent, input.Timeout, 0);

    if (runId == 0) {
      var foundRunId = await CheckWorkflowInProgressAsync(context, workflowName);
      if (!foundRunId.HasValue) {
        throw new TimeoutException($"Workflow in-progress event timed out after {input.Timeout} and no workflow run was found");
      }
      runId = foundRunId.Value;
    }

    var currentAttempt = 1;
    var success = await context.WaitForExternalEvent<bool?>(WorkflowWebhook.WorkflowCompletedEvent, input.Timeout, null);

    if (await CheckWorkflowSuccessAsync(context, success, runId, currentAttempt, input.MaxAttempts)) {
      return;
    }

    while (currentAttempt < input.MaxAttempts) {
      currentAttempt++;
      await context.CallActivityAsync<bool>(nameof(RerunFailedJobActivity), runId);
      success = await context.WaitForExternalEvent<bool?>(WorkflowWebhook.WorkflowCompletedEvent, input.Timeout, null);

      if (await CheckWorkflowSuccessAsync(context, success, runId, currentAttempt, input.MaxAttempts)) {
        return;
      }
    }
  }
}

