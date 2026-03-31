using System.ComponentModel.DataAnnotations;

namespace Template.Functions.GithubWorkflowOrchestrator;

public class TriggerInput {
  [Required] public string InstanceId { get; set; } = null!;

  [Required] public string WorkflowFile { get; set; } = null!;
}
