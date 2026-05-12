using System.ComponentModel.DataAnnotations;

namespace Template.Shared.Github;

public class GithubWorkflowOptions {
  private static readonly TimeSpan[] DefaultRerunTriggerRetryDelays = [
    TimeSpan.FromSeconds(15),
    TimeSpan.FromSeconds(30),
    TimeSpan.FromMinutes(1)
  ];

  /// <summary>The GitHub organisation or user account that owns the target repository.</summary>
  [Required] public string Owner { get; set; } = null!;
  [Required] public string Repo { get; set; } = null!;
  [Required] public string Branch { get; set; } = null!;

  public int MaxAttempts { get; set; } = 5;
  public TimeSpan[] RerunTriggerRetryDelays { get; set; } = [];
  public int WorkflowTimeoutHours { get; set; } = 12;

  public TimeSpan[] GetRerunTriggerRetryDelayValues() {
    return RerunTriggerRetryDelays.Length == 0
      ? DefaultRerunTriggerRetryDelays
      : RerunTriggerRetryDelays;
  }

  public TimeSpan WorkflowTimeout => TimeSpan.FromHours(WorkflowTimeoutHours);
}
