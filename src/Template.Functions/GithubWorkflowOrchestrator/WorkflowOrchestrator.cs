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

public record OrchestratorInput(int MaxAttempts, TimeSpan Timeout);

public class WorkflowOrchestrator(IOptionsMonitor<GithubAppOptions> optionsMonitor) {

  [Function(nameof(StartWorkflow))]
  public async Task<HttpResponseData> StartWorkflow(
    [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "workflow/start")] HttpRequestData req,
    [DurableClient] DurableTaskClient client) {

    var options = optionsMonitor.CurrentValue;
    var input = new OrchestratorInput(options.MaxAttempts, options.WorkflowTimeout);

    var instanceId = await client.ScheduleNewOrchestrationInstanceAsync(nameof(WorkflowOrchestrator), input);

    var response = req.CreateResponse(HttpStatusCode.OK);
    await response.WriteAsJsonAsync(new {
      Id = instanceId,
    });

    return response;
  }

  private async Task<bool> CheckWorkflowSuccessAsync(TaskOrchestrationContext context, long runId, int currentAttempt, int maxAttempts) {
    var logger = context.CreateReplaySafeLogger<WorkflowOrchestrator>();
    logger.LogWarning("Workflow completion event timed out on attempt {CurrentAttempt} of {MaxAttempts}",
        currentAttempt, maxAttempts);

    var workflowStatus = await context.CallActivityAsync<WorkflowRunInfo?>(nameof(GetWorkflowRunStatusActivity), runId);

    if (workflowStatus is not { Status: WorkflowRunStatus.Completed }) {
      return true;
    }

    return workflowStatus.Conclusion == WorkflowRunConclusion.Success;
  }

  [Function(nameof(WorkflowOrchestrator))]
  public async Task RunAsync(
    [OrchestrationTrigger] TaskOrchestrationContext context) {
    var input = context.GetInput<OrchestratorInput>();
    if (input == null) return;

    await context.CallActivityAsync(nameof(TriggerWorkflowActivity), context.InstanceId);
    var runId = await context.WaitForExternalEvent<long>(WorkflowWebhook.WorkflowInProgressEvent, input.Timeout, 0);

    if (runId == 0) {
      throw new TimeoutException($"Workflow timed out after waiting for events for {input.Timeout}");
    }

    var currentAttempt = 1;
    var success = await context.WaitForExternalEvent<bool?>(WorkflowWebhook.WorkflowCompletedEvent, input.Timeout, null);

    if ((!success.HasValue && await CheckWorkflowSuccessAsync(context, runId, currentAttempt, input.MaxAttempts))
        || (success.HasValue && success.Value)) {
      return;
    }



    while (currentAttempt < input.MaxAttempts) {
      currentAttempt++;
      await context.CallActivityAsync<bool>(nameof(RerunFailedJobActivity), runId);
      success = await context.WaitForExternalEvent<bool?>(WorkflowWebhook.WorkflowCompletedEvent, input.Timeout, null);

      if ((!success.HasValue && await CheckWorkflowSuccessAsync(context, runId, currentAttempt, input.MaxAttempts))
          || (success.HasValue && success.Value)) {
        return;
      }
    }
  }
}

