using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Options;
using Octokit;
using Template.Shared.Proxy;
using Template.Shared.Github;

namespace Template.Functions.GithubWorkflowOrchestrator;

public class TriggerWorkflowActivity(
  IOptionsMonitor<GithubAppOptions> optionsMonitor,
  IGitHubClientFactory gitHubClientFactory) {

  [Function(nameof(TriggerWorkflowActivity))]
  public async Task<string> RunAsync([ActivityTrigger] TriggerInput input) {
    var options = optionsMonitor.CurrentValue;
    var githubClient = await gitHubClientFactory.GetOrCreateClientAsync();

    var workflowName = $"{FunctionAppIdentifiers.InternalApi}-{input.InstanceId}";

    var workflowDispatchRequest = new CreateWorkflowDispatch(options.Branch) {
      Inputs = new Dictionary<string, object>() { ["workflowName"] = workflowName }
    };

    await githubClient.Actions.Workflows.CreateDispatch(options.Owner, options.Repo,
      input.WorkflowFile, workflowDispatchRequest);

    return workflowName;
  }
}
