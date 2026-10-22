using Azure.Data.Tables;
using Microsoft.Azure.Functions.Worker;
using Microsoft.DurableTask;
using Microsoft.DurableTask.Client;

namespace Template.Functions;

// TEMPORARY test functions. They are copied into src/Template.Functions only to publish a test package and are never
// merged. They record every start and end of a unit of work to the 'inflighttest' table, so that a rerun after the app
// stops shows up as a second 'start' row. They have no side effects outside that table.
public class InflightTest {
  private const string TableName = "inflighttest";

  public class Job {
    public string Id { get; set; } = "";
    public string Step { get; set; } = "";
    public int Seconds { get; set; }
  }

  [Function("InflightQueueJob")]
  public async Task QueueJob(
    [QueueTrigger("inflight-job")] Job job,
    [TableInput(TableName)] TableClient table,
    long dequeueCount) {
    await Record(table, job.Id, "queue", "start", dequeueCount);
    // deliberately ignores cancellation, like real work that doesn't check for shutdown
    await Task.Delay(TimeSpan.FromSeconds(job.Seconds));
    await Record(table, job.Id, "queue", "end", dequeueCount);
  }

  [Function("InflightStarter")]
  public async Task Start([QueueTrigger("inflight-start")] Job job, [DurableClient] DurableTaskClient client) {
    await client.ScheduleNewOrchestrationInstanceAsync("InflightOrchestrator", job, new StartOrchestrationOptions(job.Id));
  }

  [Function("InflightOrchestrator")]
  public static async Task<string> Orchestrate([OrchestrationTrigger] TaskOrchestrationContext context) {
    var job = context.GetInput<Job>()!;
    await context.CallActivityAsync("InflightActivity", new Job { Id = job.Id, Step = "A", Seconds = job.Seconds });
    await context.CreateTimer(context.CurrentUtcDateTime.AddSeconds(job.Seconds / 2), CancellationToken.None);
    await context.CallActivityAsync("InflightActivity", new Job { Id = job.Id, Step = "B", Seconds = 5 });
    return "done";
  }

  [Function("InflightActivity")]
  public async Task Activity([ActivityTrigger] Job job, [TableInput(TableName)] TableClient table) {
    await Record(table, job.Id, $"activity-{job.Step}", "start", 0);
    await Task.Delay(TimeSpan.FromSeconds(job.Seconds));
    await Record(table, job.Id, $"activity-{job.Step}", "end", 0);
  }

  private static async Task Record(TableClient table, string id, string kind, string evt, long attempt) {
    await table.CreateIfNotExistsAsync();
    var at = DateTimeOffset.UtcNow;
    var entity = new TableEntity(id, $"{at:yyyyMMddHHmmssfff}-{kind}-{evt}-{Guid.NewGuid():N}") {
      { "Kind", kind },
      { "Event", evt },
      { "Attempt", attempt },
      { "Instance", Environment.GetEnvironmentVariable("WEBSITE_INSTANCE_ID") ?? Environment.MachineName },
      { "At", at }
    };
    await table.AddEntityAsync(entity);
  }
}
