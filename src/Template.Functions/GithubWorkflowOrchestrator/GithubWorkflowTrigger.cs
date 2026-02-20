using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using Microsoft.DurableTask.Client;
using Microsoft.Extensions.Options;
using Template.Shared.Github;
using FromBody = Microsoft.Azure.Functions.Worker.Http.FromBodyAttribute;

namespace Template.Functions.GithubWorkflowOrchestrator;

public class GithubWorkflowTrigger(IOptionsMonitor<GithubAppOptions> optionsMonitor) {

  [Function(nameof(GithubWorkflowTrigger))]
  public async Task<IActionResult> RunAsync(
    [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "workflow/start")] HttpRequest _,
    [DurableClient] DurableTaskClient client,
    [@FromBody] StartWorkflowRequest workflowRequest) {

    var options = optionsMonitor.CurrentValue;
    var input = new OrchestratorInput {
      MaxAttempts = options.MaxAttempts,
      Timeout = options.WorkflowTimeout,
      RerunEntireWorkflow = workflowRequest.RerunEntireWorkflow,
      WorkflowFile = workflowRequest.WorkflowFile
    };

    var instanceId = await client.ScheduleNewOrchestrationInstanceAsync(nameof(GithubWorkflowOrchestrator), input);

    return new OkObjectResult(new {
      Id = instanceId,
    });
  }
}
