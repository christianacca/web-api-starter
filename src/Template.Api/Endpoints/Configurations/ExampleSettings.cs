namespace Template.Api.Endpoints.Configurations;

public class ExampleSettings {
  public bool BoolScalar { get; set; }
  public string? StringScalar { get; set; }
  public IList<string> StringCollection { get; set; } = new List<string>();
}