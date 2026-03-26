using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Options;
using Octokit;
using System.Data.Common;
using System.Text.Json;
using Template.Shared.Proxy;
using Template.Shared.Github;

namespace Template.Functions.GithubWorkflowOrchestrator;

public class TriggerWorkflowActivity(
  IOptionsMonitor<GithubAppOptions> optionsMonitor,
  IGitHubClientFactory gitHubClientFactory,
  IConfiguration configuration,
  IHostEnvironment hostEnvironment) {

  [Function(nameof(TriggerWorkflowActivity))]
  public async Task<string> RunAsync([ActivityTrigger] TriggerInput input) {
    var options = optionsMonitor.CurrentValue;
    var githubClient = await gitHubClientFactory.GetOrCreateClientAsync();

    var workflowName = $"{FunctionAppIdentifiers.InternalApi}-{input.InstanceId}";
    var workflowInputs = new Dictionary<string, object>() { ["workflowName"] = workflowName };
    var localVerificationDirective = BuildLocalVerificationDirective();
    if (!string.IsNullOrWhiteSpace(localVerificationDirective)) {
      workflowInputs["localVerification"] = localVerificationDirective;
    }

    var workflowDispatchRequest = new CreateWorkflowDispatch(options.Branch) {
      Inputs = workflowInputs
    };

    await githubClient.Actions.Workflows.CreateDispatch(options.Owner, options.Repo,
      input.WorkflowFile, workflowDispatchRequest);

    return workflowName;
  }

  private string? BuildLocalVerificationDirective() {
    if (!hostEnvironment.IsDevelopment()) {
      return null;
    }

    var queueEndpoint = configuration["Github:LocalVerification:QueueEndpoint"];
    if (string.IsNullOrWhiteSpace(queueEndpoint)) {
      return null;
    }

    var azureWebJobsStorage = configuration.GetValue<string>("AzureWebJobsStorage");
    if (string.IsNullOrWhiteSpace(azureWebJobsStorage)) {
      throw new InvalidOperationException("Github:LocalVerification:QueueEndpoint requires AzureWebJobsStorage to be configured.");
    }

    return JsonSerializer.Serialize(new {
      storageConnectionString = BuildQueueConnectionString(azureWebJobsStorage, queueEndpoint)
    });
  }

  private static string BuildQueueConnectionString(string azureWebJobsStorage, string queueEndpoint) {
    var connectionStringBuilder = new DbConnectionStringBuilder {
      ConnectionString = azureWebJobsStorage
    };

    if (!connectionStringBuilder.ContainsKey("AccountName") || string.IsNullOrWhiteSpace(connectionStringBuilder["AccountName"]?.ToString())) {
      throw new InvalidOperationException("AzureWebJobsStorage must include AccountName for local workflow verification.");
    }

    if (!connectionStringBuilder.ContainsKey("AccountKey") || string.IsNullOrWhiteSpace(connectionStringBuilder["AccountKey"]?.ToString())) {
      throw new InvalidOperationException("AzureWebJobsStorage must include AccountKey for local workflow verification.");
    }

    connectionStringBuilder["DefaultEndpointsProtocol"] = "https";
    connectionStringBuilder["QueueEndpoint"] = queueEndpoint.TrimEnd('/');

    if (connectionStringBuilder.ContainsKey("BlobEndpoint")) {
      connectionStringBuilder.Remove("BlobEndpoint");
    }

    if (connectionStringBuilder.ContainsKey("TableEndpoint")) {
      connectionStringBuilder.Remove("TableEndpoint");
    }

    return connectionStringBuilder.ConnectionString;
  }
}
