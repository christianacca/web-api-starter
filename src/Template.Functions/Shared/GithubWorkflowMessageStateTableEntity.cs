using Template.Functions.GithubWorkflowOrchestrator;

namespace Template.Functions.Shared;

public sealed class GithubWorkflowMessageStateTableEntity : TypedTableEntityBase {
  public const string PartitionKeyValue = "github-workflow-message";
  public const string ProcessingStatus = "Processing";
  public const string CompletedStatus = "Completed";

  public Guid QueueMessageId { get; set; }
  public string Status { get; set; } = ProcessingStatus;

  public static GithubWorkflowMessageStateTableEntity Create(
    Guid queueMessageId,
    GithubWorkflowQueueMessage workflowMessage) {
    var payload = workflowMessage.Payload;

    return new GithubWorkflowMessageStateTableEntity {
      PartitionKey = PartitionKeyValue,
      RowKey = CreateRowKey(workflowMessage.MessageType, payload.InstanceId, payload.RunId, payload.RunAttempt),
      QueueMessageId = queueMessageId,
      Status = ProcessingStatus
    };
  }

  public bool IsCompleted => string.Equals(Status, CompletedStatus, StringComparison.Ordinal);

  public void MarkCompleted() {
    Status = CompletedStatus;
  }

  public static string CreateRowKey(string messageType, string instanceId, long runId, int runAttempt) {
    return string.Join('|', messageType, instanceId, runId, runAttempt);
  }
}