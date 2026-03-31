using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Options;
using Octokit;
using System.Data.Common;
using System.Text.Json;
using Template.Shared.Github;

namespace Template.Functions.GithubWorkflow;

public class TriggerWorkflowActivity(
  IOptionsMonitor<GithubAppOptions> optionsMonitor,
  IGitHubClientFactory gitHubClientFactory,
  FunctionAppName functionAppName,
  IConfiguration configuration,
  IHostEnvironment hostEnvironment) {
  private const string LocalVerificationQueueEndpointKey = "Github:LocalVerification:QueueEndpoint";
  private const string AzureWebJobsStorageKey = "AzureWebJobsStorage";
  private const string AccountNameKey = "AccountName";
  private const string AccountKeyKey = "AccountKey";
  private const string DefaultEndpointsProtocolKey = "DefaultEndpointsProtocol";
  private const string QueueEndpointKey = "QueueEndpoint";
  private const string BlobEndpointKey = "BlobEndpoint";
  private const string TableEndpointKey = "TableEndpoint";

  [Function(nameof(TriggerWorkflowActivity))]
  public async Task<string> RunAsync([ActivityTrigger] TriggerInput input) {
    var options = optionsMonitor.CurrentValue;
    var githubClient = await gitHubClientFactory.GetOrCreateClientAsync();

    var workflowName = $"{functionAppName.Value}-{input.InstanceId}";
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

    var queueEndpoint = configuration[LocalVerificationQueueEndpointKey];
    if (string.IsNullOrWhiteSpace(queueEndpoint)) {
      return null;
    }

    var azureWebJobsStorage = configuration.GetValue<string>(AzureWebJobsStorageKey);
    if (string.IsNullOrWhiteSpace(azureWebJobsStorage)) {
      throw new InvalidOperationException($"{LocalVerificationQueueEndpointKey} requires {AzureWebJobsStorageKey} to be configured.");
    }

    return JsonSerializer.Serialize(new {
      storageConnectionString = BuildQueueConnectionString(azureWebJobsStorage, queueEndpoint)
    });
  }

  private static string BuildQueueConnectionString(string azureWebJobsStorage, string queueEndpoint) {
    var connectionStringBuilder = new DbConnectionStringBuilder {
      ConnectionString = azureWebJobsStorage
    };

    GetRequiredConnectionStringValue(connectionStringBuilder, AccountNameKey);
    GetRequiredConnectionStringValue(connectionStringBuilder, AccountKeyKey);

    connectionStringBuilder[DefaultEndpointsProtocolKey] = "https";
    connectionStringBuilder[QueueEndpointKey] = queueEndpoint.TrimEnd('/');

    RemoveConnectionStringValue(connectionStringBuilder, BlobEndpointKey);
    RemoveConnectionStringValue(connectionStringBuilder, TableEndpointKey);

    return connectionStringBuilder.ConnectionString;
  }

  private static string GetRequiredConnectionStringValue(DbConnectionStringBuilder connectionStringBuilder, string key) {
    if (!connectionStringBuilder.ContainsKey(key) || string.IsNullOrWhiteSpace(connectionStringBuilder[key]?.ToString())) {
      throw new InvalidOperationException($"{AzureWebJobsStorageKey} must include {key} for local workflow verification.");
    }

    return connectionStringBuilder[key].ToString()!;
  }

  private static void RemoveConnectionStringValue(DbConnectionStringBuilder connectionStringBuilder, string key) {
    if (connectionStringBuilder.ContainsKey(key)) {
      connectionStringBuilder.Remove(key);
    }
  }
}
