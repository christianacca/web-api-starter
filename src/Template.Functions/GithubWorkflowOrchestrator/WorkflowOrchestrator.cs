using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.DurableTask;
using Microsoft.DurableTask.Client;
using Microsoft.Extensions.Options;
using System.Net;
using Template.Shared.Github;

namespace Template.Functions.GithubWorkflowOrchestrator;

public record OrchestratorInput(int MaxAttempts, TimeSpan Timeout);

public class WorkflowOrchestrator(IOptionsMonitor<GithubAppOptions> optionsMonitor) {

  [Function(nameof(StartWorkflow))]
  public async Task<HttpResponseData> StartWorkflow(
    [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "workflow/start")] HttpRequestData req,
    [DurableClient] DurableTaskClient client) {

    var options = optionsMonitor.CurrentValue;
    var input = new OrchestratorInput(options.MaxAttempts, options.WorkflowTimeout);

    var instanceId = await client.ScheduleNewOrchestrationInstanceAsync(nameof(WorkflowOrchestrator), input);

    var response = req.CreateResponse(HttpStatusCode.OK);
    await response.WriteAsJsonAsync(new {
      Id = instanceId,
    });

    return response;
  }

  [Function(nameof(WorkflowOrchestrator))]
  public async Task RunAsync(
    [OrchestrationTrigger] TaskOrchestrationContext context) {

    var input = context.GetInput<OrchestratorInput>();

    if (input == null) return;

    await context.CallActivityAsync(nameof(TriggerWorkflowActivity), context.InstanceId);

    var runId = await context.WaitForExternalEvent<long>(WorkflowWebhook.WorkflowInProgressEvent, input.Timeout);

    if (runId == 0) {
      throw new TimeoutException($"Workflow did not start within timeout period of {input.Timeout}");
    }

    var currentAttempt = 1;

    var success = await context.WaitForExternalEvent<bool>(WorkflowWebhook.WorkflowCompletedEvent, input.Timeout);

    while (!success && currentAttempt < input.MaxAttempts) {
      currentAttempt++;
      await context.CallActivityAsync<bool>(nameof(RerunFailedJobActivity), runId);
      success = await context.WaitForExternalEvent<bool>(WorkflowWebhook.WorkflowCompletedEvent, input.Timeout);
    }
  }
}

