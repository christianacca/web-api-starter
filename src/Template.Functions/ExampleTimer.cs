using Azure.Data.Tables;
using Microsoft.Azure.Functions.Worker;
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

  [Function(nameof(ExampleTimer))]
  public static async Task RunAsync(
    // run twice a day at midnight and mid-day
    [TimerTrigger("0 0 */12 * * *")] TimerInfo myTimer,
    // [TimerTrigger("0 0 */12 * * *", RunOnStartup = true)] TimerInfo myTimer,
    // next line shows the standard way to get a typed entity from table storage, but it's not working as of version 1.2.0 of Microsoft.Azure.Functions.Worker.Extensions.Tables
    // [TableInput(AppState.TableName, StoragePartitionKey, StorageRowKey)] MyState? state,
    [TableInput(AppState.TableName)] TableClient tableClient,
    FunctionContext context,
    CancellationToken ct) {
    var log = context.GetLogger<ExampleTimer>();
    log.LogInformation("C# Timer trigger function executed at: {UtcNow}", DateTime.UtcNow);

    // note: we're having to explicitly fetch the entity from table storage because the TableInput attribute is not
    // working (see above)
    var state = await tableClient
      .GetEntityIfExistsAsync<MyState>(StoragePartitionKey, StorageRowKey, cancellationToken: ct);
    var currentState = MyState.GetOrCreate(state.HasValue ? state.Value : null);
    var previousRun = currentState.LastSuccessfulRun;
    currentState.LastSuccessfulRun = DateTimeOffset.UtcNow;

    // the body of the timer logic goes here
    log.LogInformation("Simulating work done by trigger using date of last run: {LastSuccessfulRun}", previousRun);

    // ... if we got here then we know that trigger code was successful, therefore record the timestamp so
    // that next time timer runs we can use this value for example to find records that have changed since the
    // last time the trigger ran successfully

    // as of version 1.2.0 of Microsoft.Azure.Functions.Worker.Extensions.Tables, we need to explicitly create table ourselves
    // hopefully that will not be required in future version of the extension
    await tableClient.CreateIfNotExistsAsync(ct);
    await tableClient.UpsertEntityAsync(currentState, TableUpdateMode.Replace, CancellationToken.None);
  }
}