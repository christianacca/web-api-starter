using Azure.Data.Tables;
using Microsoft.Azure.WebJobs;
using Microsoft.Extensions.Logging;
using Template.Functions.Shared;

namespace Template.Functions;

public class ExampleTimer {
  private const string StorageRowKey = "MyState";
  private const string StoragePartitionKey = nameof(ExampleTimer);


  public class MyState : TypedTableEntityBase {
    public DateTimeOffset LastSuccessfulRun { get; set; }

    public static MyState GetOrCreate(MyState? existing) {
      return existing != null
        ? (MyState)existing.MemberwiseClone()
        : new MyState { PartitionKey = StoragePartitionKey, RowKey = StorageRowKey };
    }
  }

  [FunctionName(nameof(ExampleTimer))]
  public static async Task RunAsync(
    [TimerTrigger("0 33 14 * * *", RunOnStartup = true)]
    TimerInfo myTimer,
    [Table(AppState.TableName, StoragePartitionKey, StorageRowKey)]
    MyState? state,
    [Table(AppState.TableName)] TableClient tableClient,
    ILogger log) {
    log.LogInformation("C# Timer trigger function executed at: {UtcNow}", DateTime.UtcNow);

    var currentState = MyState.GetOrCreate(state);
    currentState.LastSuccessfulRun = DateTimeOffset.UtcNow;

    // the body of the timer logic goes here
    log.LogInformation("Simulating work done by trigger");

    // ... if we got here then we know that trigger code was successful, therefore record the timestamp so
    // that next time timer runs we can use this value for example to find records that have changed since the
    // last time the trigger ran successfully

    await tableClient.UpsertEntityAsync(currentState, TableUpdateMode.Replace, CancellationToken.None);
  }
}