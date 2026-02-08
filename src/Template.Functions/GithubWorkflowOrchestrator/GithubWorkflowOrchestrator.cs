using Microsoft.AspNetCore.Http;
using Microsoft.Azure.Functions.Worker;
using Microsoft.DurableTask;
using Microsoft.DurableTask.Client;
using Microsoft.Extensions.Options;
using Microsoft.Extensions.Logging;
using Microsoft.AspNetCore.Mvc;
using Octokit;
using Template.Shared.Github;
using Template.Functions.Shared;
using FromBody = Microsoft.Azure.Functions.Worker.Http.FromBodyAttribute;

namespace Template.Functions.GithubWorkflowOrchestrator;

public class GithubWorkflowOrchestrator(IOptionsMonitor<GithubAppOptions> optionsMonitor) {

  [Function(nameof(TriggerGithubWorkflow))]
  public async Task<IActionResult> TriggerGithubWorkflow(
    [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "workflow/start")] HttpRequest _,
    [DurableClient] DurableTaskClient client,
    [@FromBody] StartWorkflowRequest workflowRequest) {

    var options = optionsMonitor.CurrentValue;
    var input = new OrchestratorInput {
      MaxAttempts = options.MaxAttempts,
      Timeout = options.WorkflowTimeout,
      RerunEntireWorkflow = workflowRequest.RerunEntireWorkflow,
      WorkflowFile = workflowRequest.WorkflowFile
    };

    var instanceId = await client.ScheduleNewOrchestrationInstanceAsync(nameof(GithubWorkflowOrchestrator), input);

    return new OkObjectResult(new {
      Id = instanceId,
    });
  }

  private static async Task<bool> CheckWorkflowSuccessAsync(TaskOrchestrationContext context, bool? success, long runId, int currentAttempt, int maxAttempts) {
    if (success.HasValue) {
      return success.Value;
    }

    var logger = context.CreateReplaySafeLogger<GithubWorkflowOrchestrator>();
    logger.LogWarning("Workflow completion event timed out on attempt {CurrentAttempt} of {MaxAttempts}",
        currentAttempt, maxAttempts);

    var workflowStatus = await context.CallActivityAsync<WorkflowRunInfo?>(nameof(GetWorkflowRunStatusActivity), runId);
    if (workflowStatus is not { Status: WorkflowRunStatus.Completed }) {
      return true;
    }

    return workflowStatus.Conclusion == WorkflowRunConclusion.Success;
  }

  private static async Task<long?> CheckWorkflowInProgressAsync(TaskOrchestrationContext context, string workflowName) {
    var logger = context.CreateReplaySafeLogger<GithubWorkflowOrchestrator>();
    logger.LogWarning("Workflow in-progress event timed out for workflow {WorkflowName}", workflowName);

    var runId = await context.CallActivityAsync<long?>(nameof(GetRecentWorkflowRunActivity), workflowName);

    if (!runId.HasValue) {
      logger.LogWarning("No workflow run found for workflow {WorkflowName}", workflowName);
    }

    return runId;
  }

  [Function(nameof(GithubWorkflowOrchestrator))]
  public async Task RunAsync([OrchestrationTrigger] TaskOrchestrationContext context) {
    var input = context.GetInput<OrchestratorInput>();
    if (input == null) return;

    var triggerInput = new TriggerInput {
      InstanceId = context.InstanceId,
      WorkflowFile = input.WorkflowFile
    };
    var workflowName = await context.CallActivityAsync<string>(nameof(TriggerWorkflowActivity), triggerInput);
    var runId = await context.WaitForExternalEvent<long>(GithubWebhook.WorkflowInProgressEvent, input.Timeout, 0);

    if (runId == 0) {
      var foundRunId = await CheckWorkflowInProgressAsync(context, workflowName);
      if (!foundRunId.HasValue) {
        throw new TimeoutException($"Workflow in-progress event timed out after {input.Timeout} and no workflow run was found");
      }
      runId = foundRunId.Value;
    }

    var currentAttempt = 1;
    var success = await context.WaitForExternalEvent<bool?>(GithubWebhook.WorkflowCompletedEvent, input.Timeout, null);

    if (await CheckWorkflowSuccessAsync(context, success, runId, currentAttempt, input.MaxAttempts)) {
      return;
    }

    while (currentAttempt < input.MaxAttempts) {
      currentAttempt++;
      var rerunInput = new RerunInput(runId, input.RerunEntireWorkflow);
      var rerunTriggered = await context.CallActivityAsync<bool>(nameof(RerunFailedJobActivity), rerunInput);
      if (!rerunTriggered) continue;

      success = await context.WaitForExternalEvent<bool?>(GithubWebhook.WorkflowCompletedEvent, input.Timeout, null);
      if (await CheckWorkflowSuccessAsync(context, success, runId, currentAttempt, input.MaxAttempts)) {
        return;
      }
    }
  }
}

