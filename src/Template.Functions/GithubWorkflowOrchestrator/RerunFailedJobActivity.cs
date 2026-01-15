using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Template.Shared.Github;

namespace Template.Functions.GithubWorkflowOrchestrator;

public class RerunFailedJobActivity(
  IOptionsMonitor<GithubAppOptions> optionsMonitor, 
  IGitHubClientFactory githubClientFactory,
  ILogger<RerunFailedJobActivity> logger) {

  [Function(nameof(RerunFailedJobActivity))]
  public async Task<bool> RunAsync([ActivityTrigger] long runId) {
    var client = await githubClientFactory.GetOrCreateClientAsync();
    var options = optionsMonitor.CurrentValue;

    try {
      await client.Actions.Workflows.Runs.RerunFailedJobs(options.Owner, options.Repo, runId);
      return true;
    } catch (Exception ex) {
      logger.LogError(ex, 
        "Failed to rerun failed jobs for workflow run {RunId} in {Owner}/{Repo}", 
        runId, options.Owner, options.Repo);
      return false;
    }
  }
}
