using Microsoft.Azure.Functions.Worker;
using Microsoft.DurableTask;
using Microsoft.Extensions.Logging;
using Octokit;
using Template.Functions.Shared;

namespace Template.Functions.GithubWorkflowOrchestrator;

public class GithubWorkflowOrchestrator {

  [Function(nameof(GithubWorkflowOrchestrator))]
  public static async Task RunAsync([OrchestrationTrigger] TaskOrchestrationContext context) {
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

      try {
        await context.CallActivityAsync(nameof(RerunFailedJobActivity), rerunInput);
      }
      catch (Exception) {
        var logger = context.CreateReplaySafeLogger<GithubWorkflowOrchestrator>();
        logger.LogWarning("Failed to trigger rerun for run {RunId} on attempt {CurrentAttempt}, verifying workflow status", runId, currentAttempt);

        var workflowStatus = await context.CallActivityAsync<WorkflowRunInfo?>(nameof(GetWorkflowRunStatusActivity), runId);
        if (workflowStatus == null) {
          throw new InvalidOperationException($"Failed to trigger rerun and cannot verify workflow status for run {runId} on attempt {currentAttempt}");
        }

        if (workflowStatus.RunAttempt != currentAttempt) {
          throw new InvalidOperationException($"Failed to trigger rerun for run {runId} - expected attempt {currentAttempt} but workflow is at attempt {workflowStatus.RunAttempt}");
        }
      }

      success = await context.WaitForExternalEvent<bool?>(GithubWebhook.WorkflowCompletedEvent, input.Timeout, null);
      if (await CheckWorkflowSuccessAsync(context, success, runId, currentAttempt, input.MaxAttempts)) {
        return;
      }
    }
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
}

