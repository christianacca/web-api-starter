using System.ComponentModel.DataAnnotations;

namespace Template.Functions.GithubWorkflowOrchestrator;

public class StartWorkflowRequest {
  [Required] public string WorkflowFile { get; set; } = null!;

  public bool RerunEntireWorkflow { get; set; } = false;
}
