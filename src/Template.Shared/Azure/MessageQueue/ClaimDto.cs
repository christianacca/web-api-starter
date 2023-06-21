using System.Security.Claims;

namespace Template.Shared.Azure.MessageQueue;

/// <summary>
/// Convenience class for serializing/deserializig a Claim over json
/// </summary>
public class ClaimDto {
  public string Type { get; set; } = "";
  public string Value { get; set; } = "";

  public static Claim ToClaim(ClaimDto value) {
    return new Claim(value.Type, value.Value);
  }

  public static ClaimDto From(Claim value) {
    return new ClaimDto { Type = value.Type, Value = value.Value };
  }
}