using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Octokit;
using Template.Shared.Github;

namespace Template.Functions.GithubWorkflow;

public record WorkflowRunInfo(
  WorkflowRunStatus Status,
  WorkflowRunConclusion? Conclusion,
  long RunAttempt);

public class GetWorkflowRunStatusActivity(
  IOptionsMonitor<GithubWorkflowOptions> optionsMonitor,
  IGitHubClientFactory githubClientFactory,
  ILogger<GetWorkflowRunStatusActivity> logger) {

  [Function(nameof(GetWorkflowRunStatusActivity))]
  public async Task<WorkflowRunInfo> RunAsync([ActivityTrigger] long runId) {
    var client = await githubClientFactory.GetOrCreateClientAsync();
    var options = optionsMonitor.CurrentValue;

    var workflowRun = await client.Actions.Workflows.Runs.Get(options.Owner, options.Repo, runId);

    if (!workflowRun.Status.TryParse(out var status)) {
      logger.LogError(
        "Failed to parse workflow run status '{Status}' for run {RunId} in {Owner}/{Repo}",
        workflowRun.Status, runId, options.Owner, options.Repo);
      throw new InvalidOperationException(
        $"Failed to parse workflow run status '{workflowRun.Status}' for run {runId} in {options.Owner}/{options.Repo}");
    }

    if (workflowRun.Conclusion.HasValue && workflowRun.Conclusion.Value.TryParse(out var conclusion)) {
      return new WorkflowRunInfo(status, conclusion, workflowRun.RunAttempt);
    }

    return new WorkflowRunInfo(status, null, workflowRun.RunAttempt);
  }
}
