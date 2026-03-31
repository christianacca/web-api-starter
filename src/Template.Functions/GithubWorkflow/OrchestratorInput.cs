using System.ComponentModel.DataAnnotations;

namespace Template.Functions.GithubWorkflow;

public class OrchestratorInput {
  [Required]
  [Range(1, int.MaxValue)]
  public int MaxAttempts { get; set; }

  [Required]
  [MinLength(1)]
  public TimeSpan[] RerunTriggerRetryDelays { get; set; } = null!;

  [Required] public TimeSpan Timeout { get; set; }

  [Required] public bool RerunEntireWorkflow { get; set; }

  [Required] public string WorkflowFile { get; set; } = null!;
}
