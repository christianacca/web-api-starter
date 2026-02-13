using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Options;
using Template.Shared.Github;

namespace Template.Functions.GithubWorkflowOrchestrator;

public record RerunInput(long RunId, bool RerunEntireWorkflow);

public class RerunFailedJobActivity(
  IOptionsMonitor<GithubAppOptions> optionsMonitor, 
  IGitHubClientFactory githubClientFactory) {

  [Function(nameof(RerunFailedJobActivity))]
  public async Task RunAsync([ActivityTrigger] RerunInput input) {
    var client = await githubClientFactory.GetOrCreateClientAsync();
    var options = optionsMonitor.CurrentValue;

    if (input.RerunEntireWorkflow) {
      await client.Actions.Workflows.Runs.Rerun(options.Owner, options.Repo, input.RunId);
    } else {
      await client.Actions.Workflows.Runs.RerunFailedJobs(options.Owner, options.Repo, input.RunId);
    }
  }
}
