using System.ComponentModel.DataAnnotations;

namespace Template.Functions.GithubWorkflowOrchestrator;

public class OrchestratorInput {
  [Required]
  [Range(1, int.MaxValue)]
  public int MaxAttempts { get; set; }

  [Required] public TimeSpan Timeout { get; set; }

  [Required] public bool RerunEntireWorkflow { get; set; }

  [Required] public string WorkflowFile { get; set; } = null!;
}

public class StartWorkflowRequest {
  [Required] public string WorkflowFile { get; set; } = null!;

  public bool RerunEntireWorkflow { get; set; } = false;
}

public class TriggerInput {
  [Required] public string InstanceId { get; set; } = null!;

  [Required] public string WorkflowFile { get; set; } = null!;
}

