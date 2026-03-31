using System.ComponentModel.DataAnnotations;

namespace Template.Functions.GithubWorkflow;

public class TriggerInput {
  [Required] public string InstanceId { get; set; } = null!;

  [Required] public string WorkflowFile { get; set; } = null!;

  public Dictionary<string, string>? WorkflowInputs { get; set; }
}
