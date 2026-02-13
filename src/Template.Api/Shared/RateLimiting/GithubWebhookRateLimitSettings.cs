using System.ComponentModel.DataAnnotations;

namespace Template.Api.Shared.RateLimiting;

public class GithubWebhookRateLimitSettings {
  public static readonly string PolicyName = "GithubWebhookPolicy";
  
  [Range(1, int.MaxValue)]
  public int PermitLimit { get; set; } = 100;
  
  [Range(1, 3600)]
  public int WindowInSeconds { get; set; } = 60;
  
  public TimeSpan Window => TimeSpan.FromSeconds(WindowInSeconds);
  
  public bool Enabled { get; set; } = true;
}
