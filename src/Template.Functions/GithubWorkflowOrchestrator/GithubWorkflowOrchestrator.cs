using Microsoft.Azure.Functions.Worker;
using Microsoft.DurableTask;
using Microsoft.Extensions.Logging;
using Octokit;
using Template.Functions.Shared;

namespace Template.Functions.GithubWorkflowOrchestrator;

public class GithubWorkflowOrchestrator {
  private static TaskOptions CreateWorkflowStatusRetryOptions() =>
    new(new TaskRetryOptions(new RetryPolicy(3, TimeSpan.FromSeconds(30), 2)));

  [Function(nameof(GithubWorkflowOrchestrator))]
  public static async Task RunAsync([OrchestrationTrigger] TaskOrchestrationContext context) {
    var input = context.GetInput<OrchestratorInput>();
    if (input == null) return;

    var triggerInput = new TriggerInput {
      InstanceId = context.InstanceId,
      WorkflowFile = input.WorkflowFile
    };
    var workflowName = await context.CallActivityAsync<string>(nameof(TriggerWorkflowActivity), triggerInput);
    var runId = await context.WaitForExternalEvent<long>(GithubWorkflowMessageTypes.GithubWorkflowInProgress, input.Timeout, 0);

    if (runId == 0) {
      var foundRunId = await CheckWorkflowInProgressAsync(context, workflowName);
      if (!foundRunId.HasValue) {
        throw new TimeoutException($"Workflow in-progress event timed out after {input.Timeout} and no workflow run was found");
      }
      runId = foundRunId.Value;
    }

    var currentAttempt = 1;
    var success = await context.WaitForExternalEvent<bool?>(GithubWorkflowMessageTypes.GithubWorkflowCompleted, input.Timeout, null);

    if (await CheckWorkflowSuccessAsync(context, success, runId, currentAttempt, input.MaxAttempts)) {
      return;
    }

    while (currentAttempt < input.MaxAttempts) {
      currentAttempt++;
      var rerunInput = new RerunInput(runId, input.RerunEntireWorkflow);
      var rerunStarted = await TriggerRerunWithBackoffAsync(context, rerunInput, runId, currentAttempt, input.RerunTriggerRetryDelays);

      if (!rerunStarted) {
        var logger = context.CreateReplaySafeLogger<GithubWorkflowOrchestrator>();
        logger.LogWarning(
          "Stopping retries for workflow run {RunId} after orchestration attempt {CurrentAttempt} because the rerun could not be started; preserving the known failed workflow outcome",
          runId,
          currentAttempt);
        return;
      }

      success = await context.WaitForExternalEvent<bool?>(GithubWorkflowMessageTypes.GithubWorkflowCompleted, input.Timeout, null);
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

    var workflowStatus = await context.CallActivityAsync<WorkflowRunInfo>(
      nameof(GetWorkflowRunStatusActivity),
      runId,
      CreateWorkflowStatusRetryOptions());

    if (workflowStatus.Status != WorkflowRunStatus.Completed) {
      // If the workflow is still incomplete after the completion event timeout, stop retry orchestration to avoid duplicate triggers.
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

  /// <summary>
  /// Retries the rerun trigger because GitHub can report the workflow as failed before it has fully finished
  /// its post-job cleanup, during which rerun requests are still rejected as though the run is active.
  /// This is intentionally separate from Durable activity retries because the decision to try again depends
  /// on re-checking GitHub workflow state after each failed trigger attempt.
  /// </summary>
  private static async Task<bool> TriggerRerunWithBackoffAsync(
    TaskOrchestrationContext context,
    RerunInput rerunInput,
    long runId,
    int currentAttempt,
    IReadOnlyList<TimeSpan> rerunTriggerRetryDelays) {
    var logger = context.CreateReplaySafeLogger<GithubWorkflowOrchestrator>();
    WorkflowRunInfo? lastWorkflowStatus = null;

    for (var retryIndex = 0; retryIndex < rerunTriggerRetryDelays.Count; retryIndex++) {
      var delay = rerunTriggerRetryDelays[retryIndex];

      logger.LogInformation(
        "Waiting {DelaySeconds} seconds before rerun trigger attempt {RetryAttempt} of {RetryCount} for workflow run {RunId} on orchestration attempt {CurrentAttempt}",
        delay.TotalSeconds,
        retryIndex + 1,
        rerunTriggerRetryDelays.Count,
        runId,
        currentAttempt);

      await context.CreateTimer(context.CurrentUtcDateTime.Add(delay), CancellationToken.None);

      try {
        await context.CallActivityAsync(nameof(RerunFailedJobActivity), rerunInput);
        return true;
      }
      catch (Exception ex) {
        logger.LogWarning(
          ex,
          "Failed to trigger rerun for run {RunId} on orchestration attempt {CurrentAttempt}; checking workflow status before deciding whether to retry",
          runId,
          currentAttempt);

        // A trigger exception does not prove the rerun did not happen, so re-read GitHub state before
        // deciding whether another rerun attempt is still needed.
        lastWorkflowStatus = await context.CallActivityAsync<WorkflowRunInfo>(
          nameof(GetWorkflowRunStatusActivity),
          runId,
          CreateWorkflowStatusRetryOptions());

        // Activities have at-least-once execution semantics, so the observed run attempt can legitimately
        // advance beyond the exact orchestration attempt we were trying to start before we re-check GitHub.
        if (lastWorkflowStatus.RunAttempt >= currentAttempt) {
          logger.LogInformation(
            "Workflow rerun for run {RunId} is already visible at run attempt {CurrentAttempt} after a trigger exception; proceeding with orchestration wait",
            runId,
            currentAttempt);
          return true;
        }

        logger.LogInformation(
          "Workflow run {RunId} is still at run attempt {ObservedRunAttempt} with status {ObservedStatus} after rerun trigger failure on orchestration attempt {CurrentAttempt}",
          runId,
          lastWorkflowStatus.RunAttempt,
          lastWorkflowStatus.Status,
          currentAttempt);
      }
    }

    if (lastWorkflowStatus == null) {
      throw new InvalidOperationException(
        $"Failed to trigger rerun for run {runId} on attempt {currentAttempt} and no workflow status could be observed after {rerunTriggerRetryDelays.Count} delayed retries");
    }

    var terminalWorkflowStatus = lastWorkflowStatus;

    logger.LogWarning(
      "Failed to trigger rerun for run {RunId} after {RetryCount} delayed retries; workflow remains at run attempt {ObservedRunAttempt} with status {ObservedStatus}. Treating the known failed workflow outcome as terminal.",
      runId,
      rerunTriggerRetryDelays.Count,
      terminalWorkflowStatus.RunAttempt,
      terminalWorkflowStatus.Status);

    return false;
  }
}

