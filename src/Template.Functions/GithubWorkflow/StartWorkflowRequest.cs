using System.ComponentModel.DataAnnotations;

namespace Template.Functions.GithubWorkflow;

public class StartWorkflowRequest {
  [Required] public string WorkflowFile { get; set; } = null!;

  public bool RerunEntireWorkflow { get; set; } = false;
}
