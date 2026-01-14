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
      // Use RerunFailedJobs to only rerun failed jobs, not all jobs
      // URL encode owner and repo for safety (though they come from validated config)
      var owner = Uri.EscapeDataString(options.Owner);
      var repo = Uri.EscapeDataString(options.Repo);
      var endpoint = new Uri($"repos/{owner}/{repo}/actions/runs/{runId}/rerun-failed-jobs", UriKind.Relative);
      await client.Connection.Post(endpoint, new object(), "application/vnd.github+json");
      return true;
    } catch (Exception ex) {
      logger.LogError(ex, 
        "Failed to rerun failed jobs for workflow run {RunId} in {Owner}/{Repo}", 
        runId, options.Owner, options.Repo);
      return false;
    }
  }
}
