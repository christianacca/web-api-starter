using System.Text.Json;
using Azure;
using Azure.Data.Tables;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Template.Functions.Shared;
using Template.Shared.Azure.MessageQueue;
using Template.Shared.Model;

namespace Template.Functions;

public class ExampleQueue {
  private const string QueueName = "default-queue";
  private const string StorageTable = "defaultqueuestorage";
  private ILogger<ExampleQueue> Logger { get; }

  public ExampleQueue(ILogger<ExampleQueue> logger) {
    Logger = logger;
  }

  /// <summary>
  /// Handle messages of type <see cref="MessageBody"/>
  /// </summary>
  /// <remarks>
  /// Try the following to see how the function handles messages:
  /// <list type="bullet">
  /// <item>{ "Id": "3554CA0A-C0BD-4A71-824E-A3E0D7FA47E4", "Data": "throw", "Metadata": { "MessageType": "SimpleMessage" } }</item>
  /// <item>{ "Id": "2F7CAD53-6CA6-498A-830E-C3F303F62653", "Data": "{\u0022SomeStringProp\u0022:\u0022throw\u0022,\u0022SomeBooleanProp\u0022:true}", "Metadata": { "MessageType": "ExampleMessageData" } }</item>
  /// </list>
  /// </remarks>
  [Function(nameof(ExampleQueue))]
  public async Task RunAsync(
    [QueueTrigger(QueueName)] MessageBody messageBody,
    [TableInput(StorageTable)] TableClient tableClient,
    long dequeueCount,
    CancellationToken ct) {

    Logger.LogInformation("Queue trigger function processing: {MessageType}", messageBody.Metadata.MessageType);

    var lastAttempt = dequeueCount == QueueConstants.MaxDequeueCount;
    
    try {
      switch (messageBody.Metadata.MessageType) {
        case nameof(ExampleMessageData):
          await ProcessExampleMessageAsync(messageBody, ct);
          break;
        case "SimpleMessage":
          ProcessSimpleMessage(messageBody, lastAttempt);
          break;
        default:
          throw new InvalidOperationException(
            $"No handler found for the message type '{messageBody.Metadata.MessageType}' for the queue '{QueueName}'");
      }
    }
    catch (Exception ex) when (lastAttempt) {
      // store exception dto so that the details are available to the queue trigger handling the poison message queue...
      
      // as of version 1.2.0 of Microsoft.Azure.Functions.Worker.Extensions.Tables, we need to explicitly create table ourselves
      // hopefully that will not be required in future version of the extension
      await tableClient.CreateIfNotExistsAsync(ct);
      
      await tableClient
        .UpsertEntityAsync(MessageExceptionTableEntity.Create(messageBody.Id, ex), TableUpdateMode.Replace, ct);
      throw;
    }
  }

  /// <summary>
  /// Handle messages that originally arrived at the queue referenced by <see cref="QueueName"/> that have failed
  /// to be processed
  /// </summary>
  /// <remarks>
  /// If our function throws, Azure function runtime will retry running our function until that message has
  /// been attempted n number of times as by QueueConstants.MaxDequeueCount
  /// thereafter it will leave the message in the queue. the runtime should then (untested) delete old messages that are
  /// older than the message time-to-live (ttl) date (which will be set by the runtime to the default of 7 days).
  /// in that way the poison queue is also acting like a short lived dead letter queue
  /// </remarks>
  [Function($"{nameof(ExampleQueue)}ExceptionHandler")]
  public async Task RunExceptionHandler(
    [QueueTrigger($"{QueueName}-poison")] MessageBody messageBody,
    [TableInput(StorageTable)] TableClient tableClient,
    long dequeueCount,
    CancellationToken ct
  ) {

    Logger.LogInformation("Queue trigger function processing: {MessageType}", messageBody.Metadata.MessageType);

    var msgExceptionResponse = await tableClient.GetEntityIfExistsAsync<MessageExceptionTableEntity>(
      MessageExceptionTableEntity.DefaultStoragePartitionKey, messageBody.Id.ToString(), cancellationToken: ct);
    var msgException = msgExceptionResponse.HasValue ? msgExceptionResponse.Value : null;

    var handled = true;
    try {
      switch (messageBody.Metadata.MessageType) {
        case nameof(ExampleMessageData):
          HandleExampleMessageException(messageBody, msgException);
          break;
        default:
          throw new InvalidOperationException(
            $"No Exception handler found for the message type '{messageBody.Metadata.MessageType}' for the queue '{QueueName}-poison'");
      }
    }
    catch (Exception) {
      handled = false;
      throw;
    }
    finally {
      if (msgException != null && (handled || dequeueCount == QueueConstants.MaxDequeueCount)) {
        // clean-up now that we're done (or given up) handling poison message
        await tableClient.DeleteEntityAsync(msgException.PartitionKey, msgException.RowKey, ETag.All, ct);
      }
    }
  }

  private void HandleExampleMessageException(MessageBody messageBody, MessageExceptionTableEntity? msgException) {
    var detail = msgException?.GetExceptionDetailObject<SanitizedProblem>();
    if (detail == null) {
      Logger.LogInformation("Simulating handling for '{MessageType}-{MessageId}",
        messageBody.Metadata.MessageType, messageBody.Id
      );
    } else {
      Logger.LogInformation("Simulating handling for '{MessageType}-{MessageId}'; Details: {@Detail}",
        messageBody.Metadata.MessageType, messageBody.Id, detail
      );
    }
  }

  // ReSharper disable once UnusedParameter.Local
  private async Task ProcessExampleMessageAsync(MessageBody message, CancellationToken ct) {
    Logger.LogInformation(
      "Simulating work done by trigger for: {MessageType}-{MessageId}", message.Metadata.MessageType, message.Id);

    var data = GetMessageData<ExampleMessageData>(message);
    if (data.SomeStringProp == "throw") {
      // simulate a poison message scenario

      var detail = new SanitizedProblem {
        IsRecoverable = false,
        Message = "You might want to consider doing something different",
        Source = "Process ExampleMessage",
        TraceId = System.Diagnostics.Activity.Current?.Id
      };
      throw new Exception("BANG") {
        // an object containing more details that will be serialized into MessageExceptionTableEntity object that
        // will be persisted to table storage so that it will be available to the poison message queue handler
        Data = { { MessageExceptionTableEntity.DetailKey, detail } }
      };
    }

    await Task.CompletedTask;
  }

  private void ProcessSimpleMessage(MessageBody message, bool lastAttempt) {
    try {
      Logger.LogInformation(
        "Simulating work done by trigger for: {MessageType}-{MessageId}", message.Metadata.MessageType, message.Id);

      if (message.Data == "throw") {
        throw new Exception("BANG"); // simulate a poison message scenario
      }
    }
    catch (Exception e) when (lastAttempt) {
      Logger.LogError(e, "Simulate handling exception 'inline' ie to NOT use the poison message queue");
    }
  }
  
  private static T GetMessageData<T>(MessageBody messageBody) {
    var data = JsonSerializer.Deserialize<T>(messageBody.Data);
    return data == null ? throw new InvalidOperationException("Message data is missing") : data;
  }
}