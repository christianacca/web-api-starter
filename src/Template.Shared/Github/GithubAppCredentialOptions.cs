using System.ComponentModel.DataAnnotations;

namespace Template.Shared.Github;

public class GithubAppCredentialOptions {
  [Required] public string AppId { get; set; } = null!;
  [Required] public string PrivateKeyPem { get; set; } = null!;
  [Required] public long InstallationId { get; set; }
}
