using Octokit;

namespace Template.Functions.GithubWorkflowOrchestrator;

/// <summary>
/// Maps between Octokit's StringEnum types (used in API responses) and custom enum types
/// (used in webhook models and internal business logic).
/// </summary>
public static class OctokitEnumMapper {
  
  /// <summary>
  /// Converts Octokit's WorkflowRunStatus StringEnum to custom WorkflowRunStatus enum.
  /// </summary>
  public static WorkflowRunStatus MapStatus(StringEnum<Octokit.WorkflowRunStatus> octokitStatus) {
    return octokitStatus.StringValue.ToLowerInvariant() switch {
      "queued" => WorkflowRunStatus.Queued,
      "in_progress" => WorkflowRunStatus.InProgress,
      "completed" => WorkflowRunStatus.Completed,
      "waiting" => WorkflowRunStatus.Waiting,
      "requested" => WorkflowRunStatus.Requested,
      "pending" => WorkflowRunStatus.Pending,
      _ => throw new ArgumentException($"Unknown workflow run status: {octokitStatus.StringValue}")
    };
  }

  /// <summary>
  /// Converts Octokit's WorkflowRunConclusion StringEnum to custom WorkflowRunConclusion enum.
  /// </summary>
  public static WorkflowRunConclusion MapConclusion(StringEnum<Octokit.WorkflowRunConclusion> octokitConclusion) {
    return octokitConclusion.StringValue.ToLowerInvariant() switch {
      "success" => WorkflowRunConclusion.Success,
      "failure" => WorkflowRunConclusion.Failure,
      "cancelled" => WorkflowRunConclusion.Cancelled,
      "neutral" => WorkflowRunConclusion.Neutral,
      "skipped" => WorkflowRunConclusion.Skipped,
      "timed_out" => WorkflowRunConclusion.TimedOut,
      "action_required" => WorkflowRunConclusion.ActionRequired,
      "stale" => WorkflowRunConclusion.Stale,
      _ => throw new ArgumentException($"Unknown workflow run conclusion: {octokitConclusion.StringValue}")
    };
  }
}
