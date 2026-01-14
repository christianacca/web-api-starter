using System.ComponentModel.DataAnnotations;

namespace Template.Shared.Github;

public class GithubAppOptions {
  [Required] public string Owner { get; set; } = null!;
  [Required] public string Repo { get; set; } = null!;
  [Required] public string Branch { get; set; } = null!;
  [Required] public string WorkflowFile { get; set; } = null!;
  [Required] public string AppId { get; set; } = null!;

  [Required] public long InstallationId { get; set; }

  [Required] public string PrivateKeyPem { get; set; } = null!;

  [Required] public string WebhookSecret { get; set; } = null!;

  public int MaxAttempts { get; set; } = 5;
  
  public int WorkflowTimeoutHours { get; set; } = 12;
  
  public TimeSpan WorkflowTimeout => TimeSpan.FromHours(WorkflowTimeoutHours);
}
