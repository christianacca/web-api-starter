namespace Template.Shared.Model; 

public class SanitizedProblem {
  public bool IsRecoverable { get; set; }
  public string Message { get; set; } = "";
  public string Source { get; set; } = "";
  public string? TraceId { get; set; }
}