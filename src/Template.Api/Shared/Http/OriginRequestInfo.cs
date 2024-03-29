namespace Template.Api.Shared.Http;

public record OriginRequestInfo {
  public static readonly Uri UnknownRequestUri = new("about:blank");
  private readonly Uri? _originRequestUri;

  public Uri OriginRequestUri {
    get => _originRequestUri ?? UnknownRequestUri;
    init => _originRequestUri = value;
  }

  /// <summary>
  /// The friendly name used to identify the upstream origin service
  /// timeout
  /// </summary>
  public string? OriginServiceName { get; init; }
}