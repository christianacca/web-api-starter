using System.ComponentModel.DataAnnotations;

namespace Template.Shared.Data;
public class EnvironmentInfoSettings {
  [Required(AllowEmptyStrings = false)] public string EnvId { get; set; } = "";
  public string InfraVersion { get; set; } = "";
}