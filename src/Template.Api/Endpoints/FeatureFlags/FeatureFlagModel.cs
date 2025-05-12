namespace Template.Api.Endpoints.FeatureFlags;

public class FeatureFlagModel {
  public bool Enabled { get; set; }
  public string Name { get; set; } = "";
}