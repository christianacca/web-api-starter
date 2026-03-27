using System.ComponentModel.DataAnnotations;

namespace Template.Shared.Github;

/// <summary>
/// Configuration options for GitHub App integration.
/// </summary>
/// <remarks>
/// This class contains all necessary settings for authenticating and interacting with GitHub
/// as a GitHub App, including repository details, authentication credentials, and workflow settings.
/// </remarks>
public class GithubAppOptions {
  private static readonly TimeSpan[] DefaultRerunTriggerRetryDelays = [
    TimeSpan.FromSeconds(15),
    TimeSpan.FromSeconds(30),
    TimeSpan.FromMinutes(1)
  ];

  /// <summary>
  /// Gets or sets the GitHub repository owner or organization name.
  /// </summary>
  [Required] public string Owner { get; set; } = null!;
  
  /// <summary>
  /// Gets or sets the GitHub repository name.
  /// </summary>
  [Required] public string Repo { get; set; } = null!;
  
  /// <summary>
  /// Gets or sets the target branch name for repository operations.
  /// </summary>
  [Required] public string Branch { get; set; } = null!;
  
  /// <summary>
  /// Gets or sets the GitHub App ID.
  /// </summary>
  /// <remarks>
  /// This identifier is assigned when creating a GitHub App and can be found in the app settings.
  /// </remarks>
  [Required] public string AppId { get; set; } = null!;

  /// <summary>
  /// Gets or sets the GitHub App installation ID.
  /// </summary>
  /// <remarks>
  /// This ID is specific to each installation of the GitHub App on a repository or organization.
  /// </remarks>
  [Required] public long InstallationId { get; set; }

  /// <summary>
  /// Gets or sets the private key in PEM format for GitHub App authentication.
  /// </summary>
  /// <remarks>
  /// This private key is used to generate JWT tokens for authenticating API requests.
  /// Should be kept secure and never committed to source control in plain text.
  /// </remarks>
  [Required] public string PrivateKeyPem { get; set; } = null!;

  /// <summary>
  /// Gets or sets the secret used to validate GitHub webhook payloads.
  /// </summary>
  /// <remarks>
  /// This secret ensures webhook requests are genuinely from GitHub and haven't been tampered with.
  /// Should be kept secure and never committed to source control in plain text.
  /// </remarks>
  [Required] public string WebhookSecret { get; set; } = null!;

  /// <summary>
  /// Gets or sets the maximum number of retry attempts for operations.
  /// </summary>
  /// <value>Defaults to 5 attempts.</value>
  public int MaxAttempts { get; set; } = 5;

  /// <summary>
  /// Gets or sets the delayed retry schedule used before attempting to trigger a GitHub workflow rerun.
  /// </summary>
  /// <value>Defaults to 15, 30, and 60 seconds.</value>
  public TimeSpan[] RerunTriggerRetryDelays { get; set; } = [];

  public TimeSpan[] GetRerunTriggerRetryDelayValues() {
    return RerunTriggerRetryDelays.Length == 0
      ? DefaultRerunTriggerRetryDelays
      : RerunTriggerRetryDelays;
  }
  
  /// <summary>
  /// Gets or sets the workflow timeout duration in hours.
  /// </summary>
  /// <value>Defaults to 12 hours.</value>
  /// <remarks>
  /// This is the internal storage value. Use <see cref="WorkflowTimeout"/> to get the TimeSpan representation.
  /// </remarks>
  public int WorkflowTimeoutHours { get; set; } = 12;
  
  /// <summary>
  /// Gets the workflow timeout as a TimeSpan.
  /// </summary>
  /// <value>A TimeSpan calculated from <see cref="WorkflowTimeoutHours"/>.</value>
  /// <remarks>
  /// This read-only property converts the hour-based timeout value into a TimeSpan for easier consumption.
  /// </remarks>
  public TimeSpan WorkflowTimeout => TimeSpan.FromHours(WorkflowTimeoutHours);
}
