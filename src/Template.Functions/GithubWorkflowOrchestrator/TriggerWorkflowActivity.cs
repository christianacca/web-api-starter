using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Options;
using Octokit;
using Template.Functions.Shared;
using Template.Shared.Github;

namespace Template.Functions.GithubWorkflowOrchestrator;

public class TriggerWorkflowActivity(
  IOptionsMonitor<GithubAppOptions> optionsMonitor,
  IGitHubClientFactory gitHubClientFactory) {

  [Function(nameof(TriggerWorkflowActivity))]
  public async Task RunAsync([ActivityTrigger] string instanceId) {
    var options = optionsMonitor.CurrentValue;
    var githubClient = await gitHubClientFactory.GetOrCreateClientAsync();

    var correlationId = $"{FunctionAppIdentifiers.InternalApi}-{instanceId}";

    var workflowDispatchRequest = new CreateWorkflowDispatch(options.Branch) {
      Inputs = new Dictionary<string, object>() { ["correlationId"] = correlationId }
    };

    await githubClient.Actions.Workflows.CreateDispatch(options.Owner, options.Repo,
      options.WorkflowFile, workflowDispatchRequest);
  }
}
