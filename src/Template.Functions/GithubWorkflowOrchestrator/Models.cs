using System.ComponentModel.DataAnnotations;

namespace Template.Functions.GithubWorkflowOrchestrator;

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

public record GithubWorkflowOrchestrationState {
  [Required] public string Stage { get; init; } = null!;

  public string? FinalOutcome { get; init; }

  [Required]
  [Range(1, int.MaxValue)]
  public int CurrentAttempt { get; init; }

  [Required]
  [Range(1, int.MaxValue)]
  public int MaxAttempts { get; init; }

  public long? RunId { get; init; }

  public long? WorkflowRunAttempt { get; init; }

  public string? WorkflowStatus { get; init; }

  public string? WorkflowConclusion { get; init; }

  public bool? WorkflowSucceeded { get; init; }

  [Required] public bool IsTerminal { get; init; }

  public string? Message { get; init; }
}

public class StartWorkflowRequest {
  [Required] public string WorkflowFile { get; set; } = null!;

  public bool RerunEntireWorkflow { get; set; } = false;
}

public class TriggerInput {
  [Required] public string InstanceId { get; set; } = null!;

  [Required] public string WorkflowFile { get; set; } = null!;
}

