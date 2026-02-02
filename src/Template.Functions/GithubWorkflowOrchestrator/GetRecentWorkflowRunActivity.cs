using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Octokit;
using Template.Shared.Github;

namespace Template.Functions.GithubWorkflowOrchestrator;

public class GetRecentWorkflowRunActivity(
  IOptionsMonitor<GithubAppOptions> optionsMonitor,
  IGitHubClientFactory githubClientFactory,
  ILogger<GetRecentWorkflowRunActivity> logger) {

  [Function(nameof(GetRecentWorkflowRunActivity))]
  public async Task<long?> RunAsync([ActivityTrigger] string workflowName) {
    var client = await githubClientFactory.GetOrCreateClientAsync();
    var options = optionsMonitor.CurrentValue;

    try {
      var workflowRuns = await client.Actions.Workflows.Runs.List(
        options.Owner, options.Repo, new WorkflowRunsRequest(),
        new ApiOptions {
          PageSize = 50,
          StartPage = 1
        });

      var matchingRun = workflowRuns.WorkflowRuns
        .OrderByDescending(run => run.CreatedAt)
        .FirstOrDefault(run => run.Name.Equals(workflowName, StringComparison.OrdinalIgnoreCase));

      return matchingRun?.Id;
    }
    catch (Exception ex) {
      logger.LogError(ex,
        "Failed to fetch recent workflow runs for workflow name {WorkflowName} in {Owner}/{Repo}",
        workflowName, options.Owner, options.Repo);
      return null;
    }
  }
}
