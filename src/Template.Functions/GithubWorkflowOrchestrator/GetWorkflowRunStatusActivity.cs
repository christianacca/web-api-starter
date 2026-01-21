using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Octokit;
using Template.Shared.Github;

namespace Template.Functions.GithubWorkflowOrchestrator;

public record WorkflowRunInfo(
  WorkflowRunStatus Status,
  WorkflowRunConclusion? Conclusion);

public class GetWorkflowRunStatusActivity(
  IOptionsMonitor<GithubAppOptions> optionsMonitor,
  IGitHubClientFactory githubClientFactory,
  ILogger<GetWorkflowRunStatusActivity> logger) {

  [Function(nameof(GetWorkflowRunStatusActivity))]
  public async Task<WorkflowRunInfo?> RunAsync([ActivityTrigger] long runId) {
    var client = await githubClientFactory.GetOrCreateClientAsync();
    var options = optionsMonitor.CurrentValue;

    try {
      var workflowRun = await client.Actions.Workflows.Runs.Get(options.Owner, options.Repo, runId);

      var status = OctokitEnumMapper.MapStatus(workflowRun.Status);
      WorkflowRunConclusion? conclusion = workflowRun.Conclusion.HasValue 
        ? OctokitEnumMapper.MapConclusion(workflowRun.Conclusion.Value) 
        : null;

      return new WorkflowRunInfo(status, conclusion);
    } catch (Exception ex) {
      logger.LogError(ex,
        "Failed to fetch workflow run status for run {RunId} in {Owner}/{Repo}",
        runId, options.Owner, options.Repo);
      return null;
    }
  }
}
