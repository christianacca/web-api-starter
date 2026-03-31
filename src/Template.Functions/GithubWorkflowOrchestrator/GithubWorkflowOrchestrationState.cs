using System.ComponentModel.DataAnnotations;
using Octokit;

namespace Template.Functions.GithubWorkflowOrchestrator;

/// <summary>
/// Describes the current orchestration lifecycle stage exposed through custom status and final output.
/// </summary>
public enum GithubWorkflowOrchestrationStage {
  /// <summary>
  /// The orchestration input could not be read or was missing.
  /// </summary>
  InvalidInput,

  /// <summary>
  /// The orchestrator is requesting that GitHub start the workflow.
  /// </summary>
  TriggeringWorkflow,

  /// <summary>
  /// The orchestrator is waiting for GitHub to report a workflow run id.
  /// </summary>
  WaitingForRunStart,

  /// <summary>
  /// The orchestrator is waiting for the workflow completion signal.
  /// </summary>
  WaitingForCompletion,

  /// <summary>
  /// The orchestrator is querying GitHub directly to reconcile workflow state.
  /// </summary>
  CheckingWorkflowStatus,

  /// <summary>
  /// The orchestrator is delaying before another rerun-trigger attempt.
  /// </summary>
  WaitingToRetryRerun,

  /// <summary>
  /// The orchestration has reached its final externally reported state.
  /// </summary>
  Completed
}

/// <summary>
/// Describes the high-level final or inferred outcome of the orchestration.
/// </summary>
public enum GithubWorkflowOrchestrationFinalOutcome {
  /// <summary>
  /// The final outcome could not be determined.
  /// </summary>
  Unknown,

  /// <summary>
  /// GitHub still reports the workflow as in progress when the orchestration stops waiting.
  /// </summary>
  InProgress,

  /// <summary>
  /// The workflow completed successfully.
  /// </summary>
  Succeeded,

  /// <summary>
  /// The workflow completed unsuccessfully or the known failed outcome was treated as terminal.
  /// </summary>
  Failed
}

/// <summary>
/// Describes the externally visible progress and terminal result of a GitHub workflow orchestration.
/// The same shape is used for in-flight <c>CustomStatus</c> updates and the final orchestration output.
/// </summary>
public record GithubWorkflowOrchestrationState {
  /// <summary>
  /// The current orchestration lifecycle stage.
  /// See <see cref="GithubWorkflowOrchestrationStage"/> for the defined values and their meanings.
  /// </summary>
  [Required] public GithubWorkflowOrchestrationStage Stage { get; init; }

  /// <summary>
  /// The high-level outcome of the orchestration when it is known.
  /// See <see cref="GithubWorkflowOrchestrationFinalOutcome"/> for the defined values.
  /// This value is typically <see langword="null"/>
  /// while the orchestration is still progressing through non-terminal stages.
  /// </summary>
  public GithubWorkflowOrchestrationFinalOutcome? FinalOutcome { get; init; }

  /// <summary>
  /// The current orchestration attempt number.
  /// Values start at <c>1</c> for the initial workflow run and increment for each rerun attempt.
  /// </summary>
  [Required]
  [Range(1, int.MaxValue)]
  public int CurrentAttempt { get; init; }

  /// <summary>
  /// The maximum number of orchestration attempts allowed for this run, including the initial attempt.
  /// Values are always greater than or equal to <c>1</c>.
  /// </summary>
  [Required]
  [Range(1, int.MaxValue)]
  public int MaxAttempts { get; init; }

  /// <summary>
  /// The GitHub Actions workflow run identifier.
  /// This is <see langword="null"/> until GitHub reports a run id or one is discovered by a fallback lookup.
  /// </summary>
  public long? RunId { get; init; }

  /// <summary>
  /// The GitHub-reported workflow run attempt number for the current <see cref="RunId"/>.
  /// This is <see langword="null"/> until GitHub workflow status has been queried.
  /// Typical values are <c>1</c> for the original run and larger values after reruns.
  /// </summary>
  public long? WorkflowRunAttempt { get; init; }

  /// <summary>
  /// The GitHub workflow status derived from Octokit's <see cref="WorkflowRunStatus"/> enum.
  /// Examples include <see cref="WorkflowRunStatus.InProgress"/> and <see cref="WorkflowRunStatus.Completed"/>.
  /// This is <see langword="null"/> when no workflow status has been queried yet.
  /// </summary>
  public WorkflowRunStatus? WorkflowStatus { get; init; }

  /// <summary>
  /// The GitHub workflow conclusion derived from Octokit's <see cref="WorkflowRunConclusion"/> enum.
  /// Examples include <see cref="WorkflowRunConclusion.Success"/> and <see cref="WorkflowRunConclusion.Failure"/>.
  /// This is <see langword="null"/> until GitHub reports a completed run with a conclusion.
  /// </summary>
  public WorkflowRunConclusion? WorkflowConclusion { get; init; }

  /// <summary>
  /// Indicates whether the orchestration currently considers the GitHub workflow successful.
  /// This is <c>true</c> for success, <c>false</c> for known non-success terminal outcomes,
  /// and <see langword="null"/> when success has not yet been determined.
  /// </summary>
  public bool? WorkflowSucceeded { get; init; }

  /// <summary>
  /// Indicates whether this state is terminal from the orchestration's perspective.
  /// <c>true</c> means the orchestration has reached its final externally reported outcome.
  /// <c>false</c> means the orchestration is still progressing.
  /// </summary>
  [Required] public bool IsTerminal { get; init; }

  /// <summary>
  /// A human-readable explanation of the current state.
  /// This is intended for operators and logs rather than strict programmatic branching,
  /// so the exact wording may change over time.
  /// </summary>
  public string? Message { get; init; }
}
