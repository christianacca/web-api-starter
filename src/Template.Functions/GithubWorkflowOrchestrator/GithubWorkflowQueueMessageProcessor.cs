using Azure;
using Azure.Data.Tables;
using Microsoft.DurableTask.Client;
using Microsoft.Extensions.Logging;
using Template.Functions.Shared;
using Template.Shared.Azure.MessageQueue;
using Template.Shared.Model;

namespace Template.Functions.GithubWorkflowOrchestrator;

public sealed class GithubWorkflowQueueMessageProcessor(ILogger<GithubWorkflowQueueMessageProcessor> logger) {
  public async Task ProcessAsync(
    MessageBody message,
    TableClient tableClient,
    DurableTaskClient client,
    bool lastAttempt,
    CancellationToken ct) {
    var workflowMessage = GithubWorkflowQueueMessageContract.Parse(message);

    await tableClient.CreateIfNotExistsAsync(ct);

    GithubWorkflowMessageStateTableEntity? processingState = null;

    try {
      processingState = await TryStartWorkflowMessageProcessingAsync(message, workflowMessage, tableClient, ct);
      if (processingState == null) {
        return;
      }

      await RaiseGithubWorkflowEventAsync(workflowMessage, client, ct);

      processingState.MarkCompleted();
      await tableClient.UpsertEntityAsync(processingState, TableUpdateMode.Replace, ct);

      logger.LogInformation(
        "Raised durable workflow event from queue message: {MessageType}-{MessageId}; InstanceId: {InstanceId}; RunId: {RunId}; RunAttempt: {RunAttempt}",
        workflowMessage.MessageType,
        message.Id,
        workflowMessage.Payload.InstanceId,
        workflowMessage.Payload.RunId,
        workflowMessage.Payload.RunAttempt);
    }
    catch (Exception ex) when (lastAttempt) {
      if (processingState != null && !processingState.IsCompleted) {
        await TryDeleteWorkflowProcessingStateAsync(tableClient, processingState, ct);
      }

      logger.LogError(
        ex,
        "Inline handling final-attempt workflow queue failure for: {MessageType}-{MessageId}; InstanceId: {InstanceId}; RunId: {RunId}; RunAttempt: {RunAttempt}",
        workflowMessage.MessageType,
        message.Id,
        workflowMessage.Payload.InstanceId,
        workflowMessage.Payload.RunId,
        workflowMessage.Payload.RunAttempt);
    }
  }

  private async Task<GithubWorkflowMessageStateTableEntity?> TryStartWorkflowMessageProcessingAsync(
    MessageBody message,
    GithubWorkflowQueueMessage workflowMessage,
    TableClient tableClient,
    CancellationToken ct) {
    var processingState = GithubWorkflowMessageStateTableEntity.Create(message.Id, workflowMessage);

    try {
      await tableClient.AddEntityAsync(processingState, ct);
      return processingState;
    }
    catch (RequestFailedException ex) when (ex.Status == 409) {
      var existing = await tableClient.GetEntityIfExistsAsync<GithubWorkflowMessageStateTableEntity>(
        processingState.PartitionKey,
        processingState.RowKey,
        cancellationToken: ct);
      var existingState = existing.HasValue ? existing.Value! : null;

      if (existingState?.IsCompleted == true) {
        logger.LogInformation(
          "Skipping duplicate workflow queue message: {MessageType}-{MessageId}; InstanceId: {InstanceId}; RunId: {RunId}; RunAttempt: {RunAttempt}",
          workflowMessage.MessageType,
          message.Id,
          workflowMessage.Payload.InstanceId,
          workflowMessage.Payload.RunId,
          workflowMessage.Payload.RunAttempt);
        return null;
      }

      logger.LogWarning(
        "Workflow queue message is already in progress; skipping duplicate delivery: {MessageType}-{MessageId}; InstanceId: {InstanceId}; RunId: {RunId}; RunAttempt: {RunAttempt}",
        workflowMessage.MessageType,
        message.Id,
        workflowMessage.Payload.InstanceId,
        workflowMessage.Payload.RunId,
        workflowMessage.Payload.RunAttempt);
      return null;
    }
  }

  private static async Task RaiseGithubWorkflowEventAsync(
    GithubWorkflowQueueMessage workflowMessage,
    DurableTaskClient client,
    CancellationToken ct) {
    switch (workflowMessage.Payload) {
      case GithubWorkflowInProgressMessageData inProgress:
        await client.RaiseEventAsync(
          inProgress.InstanceId,
          GithubWorkflowMessageTypes.GithubWorkflowInProgress,
          inProgress.RunId,
          ct);
        break;
      case GithubWorkflowCompletedMessageData completed:
        await client.RaiseEventAsync(
          completed.InstanceId,
          GithubWorkflowMessageTypes.GithubWorkflowCompleted,
          completed.IsSuccess,
          ct);
        break;
      default:
        throw new InvalidOperationException($"No durable event mapper found for workflow queue message type '{workflowMessage.MessageType}'.");
    }
  }

  private async Task TryDeleteWorkflowProcessingStateAsync(
    TableClient tableClient,
    GithubWorkflowMessageStateTableEntity processingState,
    CancellationToken ct) {
    try {
      await tableClient.DeleteEntityAsync(
        processingState.PartitionKey,
        processingState.RowKey,
        processingState.ETag == default ? ETag.All : processingState.ETag,
        ct);
    }
    catch (RequestFailedException ex) when (ex.Status == 404) {
      logger.LogWarning(
        "Workflow queue processing state was already removed for PartitionKey: {PartitionKey}; RowKey: {RowKey}",
        processingState.PartitionKey,
        processingState.RowKey);
    }
  }
}