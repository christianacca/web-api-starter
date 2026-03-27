using Microsoft.Azure.Functions.Worker;
using Microsoft.DurableTask;
using Microsoft.Extensions.Logging;
using Octokit;
using Template.Functions.Shared;

namespace Template.Functions.GithubWorkflowOrchestrator;

public class GithubWorkflowOrchestrator {
  private sealed record RerunTriggerResult(bool Started, WorkflowRunInfo? LastObservedWorkflowStatus);

  private static TaskOptions CreateWorkflowStatusRetryOptions() =>
    new(new TaskRetryOptions(new RetryPolicy(3, TimeSpan.FromSeconds(30), 2)));

  [Function(nameof(GithubWorkflowOrchestrator))]
  public static async Task<GithubWorkflowOrchestrationState> RunAsync([OrchestrationTrigger] TaskOrchestrationContext context) {
    var input = context.GetInput<OrchestratorInput>();
    if (input == null) {
      return Complete(
        context,
        CreateState(
          stage: "InvalidInput",
          currentAttempt: 1,
          maxAttempts: 1,
          finalOutcome: "Unknown",
          isTerminal: true,
          message: "The orchestration input payload was missing."));
    }

    var currentAttempt = 1;

    SetProgress(
      context,
      CreateState(
        stage: "TriggeringWorkflow",
        currentAttempt: currentAttempt,
        maxAttempts: input.MaxAttempts,
        message: "Triggering the GitHub workflow."));

    var triggerInput = new TriggerInput {
      InstanceId = context.InstanceId,
      WorkflowFile = input.WorkflowFile
    };
    var workflowName = await context.CallActivityAsync<string>(nameof(TriggerWorkflowActivity), triggerInput);

    SetProgress(
      context,
      CreateState(
        stage: "WaitingForRunStart",
        currentAttempt: currentAttempt,
        maxAttempts: input.MaxAttempts,
        message: $"Waiting for workflow '{workflowName}' to report its run id."));

    var runId = await context.WaitForExternalEvent<long>(GithubWorkflowMessageTypes.GithubWorkflowInProgress, input.Timeout, 0);

    if (runId == 0) {
      var foundRunId = await CheckWorkflowInProgressAsync(context, workflowName);
      if (!foundRunId.HasValue) {
        SetProgress(
          context,
          CreateState(
            stage: "WaitingForRunStart",
            currentAttempt: currentAttempt,
            maxAttempts: input.MaxAttempts,
            finalOutcome: "Unknown",
            isTerminal: true,
            message: $"Workflow in-progress event timed out after {input.Timeout} and no workflow run was found for '{workflowName}'."));
        throw new TimeoutException($"Workflow in-progress event timed out after {input.Timeout} and no workflow run was found");
      }
      runId = foundRunId.Value;
    }

    SetProgress(
      context,
      CreateState(
        stage: "WaitingForCompletion",
        currentAttempt: currentAttempt,
        maxAttempts: input.MaxAttempts,
        runId: runId,
        message: "Waiting for the GitHub workflow completion event."));

    var success = await context.WaitForExternalEvent<bool?>(GithubWorkflowMessageTypes.GithubWorkflowCompleted, input.Timeout, null);

    var terminalState = await EvaluateWorkflowAttemptAsync(context, success, runId, currentAttempt, input.MaxAttempts);
    if (terminalState != null) {
      return Complete(context, terminalState);
    }

    while (currentAttempt < input.MaxAttempts) {
      currentAttempt++;
      var rerunInput = new RerunInput(runId, input.RerunEntireWorkflow);
      var rerunResult = await TriggerRerunWithBackoffAsync(
        context,
        rerunInput,
        runId,
        currentAttempt,
        input.MaxAttempts,
        input.RerunTriggerRetryDelays);

      if (!rerunResult.Started) {
        var logger = context.CreateReplaySafeLogger<GithubWorkflowOrchestrator>();
        logger.LogWarning(
          "Stopping retries for workflow run {RunId} after orchestration attempt {CurrentAttempt} because the rerun could not be started; preserving the known failed workflow outcome",
          runId,
          currentAttempt);

        return Complete(
          context,
          CreateState(
            stage: "Completed",
            currentAttempt: currentAttempt,
            maxAttempts: input.MaxAttempts,
            runId: runId,
            workflowRunInfo: rerunResult.LastObservedWorkflowStatus,
            finalOutcome: "Failed",
            isTerminal: true,
            workflowSucceeded: false,
            message: "The rerun could not be started after the configured delayed retries, so the known failed workflow outcome was treated as terminal."));
      }

      SetProgress(
        context,
        CreateState(
          stage: "WaitingForCompletion",
          currentAttempt: currentAttempt,
          maxAttempts: input.MaxAttempts,
          runId: runId,
          workflowRunInfo: rerunResult.LastObservedWorkflowStatus,
          message: "Waiting for the GitHub workflow completion event after the rerun attempt."));

      success = await context.WaitForExternalEvent<bool?>(GithubWorkflowMessageTypes.GithubWorkflowCompleted, input.Timeout, null);

      terminalState = await EvaluateWorkflowAttemptAsync(context, success, runId, currentAttempt, input.MaxAttempts);
      if (terminalState != null) {
        return Complete(context, terminalState);
      }
    }

    return Complete(
      context,
      CreateState(
        stage: "Completed",
        currentAttempt: currentAttempt,
        maxAttempts: input.MaxAttempts,
        runId: runId,
        finalOutcome: "Failed",
        isTerminal: true,
        workflowStatus: WorkflowRunStatus.Completed,
        workflowConclusion: WorkflowRunConclusion.Failure,
        workflowSucceeded: false,
        message: "The workflow reported failure on the final configured orchestration attempt."));
  }

  private static async Task<GithubWorkflowOrchestrationState?> EvaluateWorkflowAttemptAsync(
    TaskOrchestrationContext context,
    bool? success,
    long runId,
    int currentAttempt,
    int maxAttempts) {
    if (success.HasValue) {
      if (success.Value) {
        return CreateState(
          stage: "Completed",
          currentAttempt: currentAttempt,
          maxAttempts: maxAttempts,
          runId: runId,
          finalOutcome: "Succeeded",
          isTerminal: true,
          workflowStatus: WorkflowRunStatus.Completed,
          workflowConclusion: WorkflowRunConclusion.Success,
          workflowSucceeded: true,
          message: "The GitHub workflow completed successfully.");
      }

      if (currentAttempt >= maxAttempts) {
        return CreateState(
          stage: "Completed",
          currentAttempt: currentAttempt,
          maxAttempts: maxAttempts,
          runId: runId,
          finalOutcome: "Failed",
          isTerminal: true,
          workflowStatus: WorkflowRunStatus.Completed,
          workflowConclusion: WorkflowRunConclusion.Failure,
          workflowSucceeded: false,
          message: "The GitHub workflow completed with failure on the final configured orchestration attempt.");
      }

      return null;
    }

    var logger = context.CreateReplaySafeLogger<GithubWorkflowOrchestrator>();
    logger.LogWarning("Workflow completion event timed out on attempt {CurrentAttempt} of {MaxAttempts}",
        currentAttempt, maxAttempts);

    SetProgress(
      context,
      CreateState(
        stage: "CheckingWorkflowStatus",
        currentAttempt: currentAttempt,
        maxAttempts: maxAttempts,
        runId: runId,
        message: "The workflow completion event timed out, so GitHub workflow status is being checked directly."));

    var workflowStatus = await context.CallActivityAsync<WorkflowRunInfo>(
      nameof(GetWorkflowRunStatusActivity),
      runId,
      CreateWorkflowStatusRetryOptions());

    if (workflowStatus.Status != WorkflowRunStatus.Completed) {
      // If the workflow is still incomplete after the completion event timeout, stop retry orchestration to avoid duplicate triggers.
      return CreateState(
        stage: "Completed",
        currentAttempt: currentAttempt,
        maxAttempts: maxAttempts,
        runId: runId,
        workflowRunInfo: workflowStatus,
        finalOutcome: "InProgress",
        isTerminal: true,
        message: "The completion event timed out, but GitHub still reports the workflow as in progress, so the orchestration stopped to avoid duplicate triggers.");
    }

    if (workflowStatus.Conclusion == WorkflowRunConclusion.Success) {
      return CreateState(
        stage: "Completed",
        currentAttempt: currentAttempt,
        maxAttempts: maxAttempts,
        runId: runId,
        workflowRunInfo: workflowStatus,
        finalOutcome: "Succeeded",
        isTerminal: true,
        workflowSucceeded: true,
        message: "The GitHub workflow completed successfully after the completion event timeout was cross-checked against GitHub.");
    }

    if (currentAttempt >= maxAttempts) {
      return CreateState(
        stage: "Completed",
        currentAttempt: currentAttempt,
        maxAttempts: maxAttempts,
        runId: runId,
        workflowRunInfo: workflowStatus,
        finalOutcome: "Failed",
        isTerminal: true,
        workflowSucceeded: false,
        message: "The GitHub workflow completed with failure on the final configured orchestration attempt.");
    }

    return null;
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
  private static async Task<RerunTriggerResult> TriggerRerunWithBackoffAsync(
    TaskOrchestrationContext context,
    RerunInput rerunInput,
    long runId,
    int currentAttempt,
    int maxAttempts,
    IReadOnlyList<TimeSpan> rerunTriggerRetryDelays) {
    var logger = context.CreateReplaySafeLogger<GithubWorkflowOrchestrator>();
    WorkflowRunInfo? lastWorkflowStatus = null;

    for (var retryIndex = 0; retryIndex < rerunTriggerRetryDelays.Count; retryIndex++) {
      var delay = rerunTriggerRetryDelays[retryIndex];

      SetProgress(
        context,
        CreateState(
          stage: "WaitingToRetryRerun",
          currentAttempt: currentAttempt,
          maxAttempts: maxAttempts,
          runId: runId,
          workflowRunInfo: lastWorkflowStatus,
          message: $"Waiting {delay.TotalSeconds} seconds before rerun trigger attempt {retryIndex + 1} of {rerunTriggerRetryDelays.Count}."));

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
        return new RerunTriggerResult(true, lastWorkflowStatus);
      }
      catch (Exception ex) {
        logger.LogWarning(
          ex,
          "Failed to trigger rerun for run {RunId} on orchestration attempt {CurrentAttempt}; checking workflow status before deciding whether to retry",
          runId,
          currentAttempt);

        SetProgress(
          context,
          CreateState(
            stage: "CheckingWorkflowStatus",
            currentAttempt: currentAttempt,
            maxAttempts: maxAttempts,
            runId: runId,
            workflowRunInfo: lastWorkflowStatus,
            message: "The rerun trigger failed, so GitHub workflow status is being checked directly before deciding whether another rerun attempt is needed."));

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
          return new RerunTriggerResult(true, lastWorkflowStatus);
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

    return new RerunTriggerResult(false, terminalWorkflowStatus);
  }

  private static GithubWorkflowOrchestrationState CreateState(
    string stage,
    int currentAttempt,
    int maxAttempts,
    long? runId = null,
    WorkflowRunInfo? workflowRunInfo = null,
    string? finalOutcome = null,
    bool isTerminal = false,
    bool? workflowSucceeded = null,
    WorkflowRunStatus? workflowStatus = null,
    WorkflowRunConclusion? workflowConclusion = null,
    string? message = null) {
    var effectiveWorkflowStatus = workflowRunInfo?.Status ?? workflowStatus;
    var effectiveWorkflowConclusion = workflowRunInfo?.Conclusion ?? workflowConclusion;
    var effectiveWorkflowRunAttempt = workflowRunInfo?.RunAttempt;

    return new GithubWorkflowOrchestrationState {
      Stage = stage,
      FinalOutcome = finalOutcome,
      CurrentAttempt = currentAttempt,
      MaxAttempts = maxAttempts,
      RunId = runId,
      WorkflowRunAttempt = effectiveWorkflowRunAttempt,
      WorkflowStatus = effectiveWorkflowStatus?.ToString(),
      WorkflowConclusion = effectiveWorkflowConclusion?.ToString(),
      WorkflowSucceeded = workflowSucceeded,
      IsTerminal = isTerminal,
      Message = message
    };
  }

  private static void SetProgress(TaskOrchestrationContext context, GithubWorkflowOrchestrationState state) {
    context.SetCustomStatus(state);
  }

  private static GithubWorkflowOrchestrationState Complete(TaskOrchestrationContext context, GithubWorkflowOrchestrationState state) {
    context.SetCustomStatus(state);
    return state;
  }
}

