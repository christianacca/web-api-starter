using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Template.Shared.Github;

namespace Template.Functions.GithubWorkflowOrchestrator;

public record RerunInput(long RunId, bool RerunEntireWorkflow);

public class RerunFailedJobActivity(
  IOptionsMonitor<GithubAppOptions> optionsMonitor, 
  IGitHubClientFactory githubClientFactory,
  ILogger<RerunFailedJobActivity> logger) {

  [Function(nameof(RerunFailedJobActivity))]
  public async Task<bool> RunAsync([ActivityTrigger] RerunInput input) {
    var client = await githubClientFactory.GetOrCreateClientAsync();
    var options = optionsMonitor.CurrentValue;

    try {
      if (input.RerunEntireWorkflow) {
        await client.Actions.Workflows.Runs.Rerun(options.Owner, options.Repo, input.RunId);
      } else {
        await client.Actions.Workflows.Runs.RerunFailedJobs(options.Owner, options.Repo, input.RunId);
      }
      return true;
    } catch (Exception ex) {
      var action = input.RerunEntireWorkflow ? "rerun workflow" : "rerun failed jobs";
      logger.LogError(ex, 
        "Failed to {Action} for workflow run {RunId} in {Owner}/{Repo}", 
        action, input.RunId, options.Owner, options.Repo);
      return false;
    }
  }
}
