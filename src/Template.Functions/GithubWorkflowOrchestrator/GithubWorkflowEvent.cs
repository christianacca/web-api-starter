namespace Template.Functions.GithubWorkflowOrchestrator;

// GitHub Workflow Run Webhook Event Models
// These models must be an exact copy of the webhook payload structure documented at:
// https://docs.github.com/en/webhooks/webhook-events-and-payloads
// 
// Note: Octokit v14.0.0 does not include webhook event payload models. Octokit primarily provides
// models for the REST API responses, but webhook payloads have a different structure and are not
// included in the Octokit package. Therefore, we need to define these models manually based on the
// official GitHub webhook documentation.

public enum WorkflowRunAction
{
  Completed,
  Requested,
  InProgress
}

public enum WorkflowRunStatus
{
  Queued,
  InProgress,
  Completed,
  Waiting,
  Requested,
  Pending
}

public enum WorkflowRunConclusion
{
  Success,
  Failure,
  Cancelled,
  Neutral,
  Skipped,
  TimedOut,
  ActionRequired,
  Stale
}

public record GitHubWorkflowRunEvent(
  WorkflowRunAction Action,
  GithubWorkflowRun WorkflowRun,
  GithubRepository Repository
);

public record GithubWorkflowRun(
  long Id,
  string Name,
  string HeadBranch,
  string Path,
  string DisplayTitle,
  string Event,
  WorkflowRunStatus Status,
  long WorkflowId,
  long CheckSuiteId,
  string Url,
  string RerunUrl,
  string WorkflowUrl,
  WorkflowRunConclusion? Conclusion
);

public record GithubRepository(
  long Id,
  string Name,
  string FullName,
  bool Private,
  string Url,
  string HtmlUrl,
  GithubOwner Owner
);

public record GithubOwner(
  string Login,
  long Id,
  string Type
);

