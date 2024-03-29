using System.Reflection;

namespace Template.Shared.Util;

public record ProductVersionParseOptions {
  public bool ShortCommitSha { get; init; } = true;
  public static ProductVersionParseOptions Default => new();
}

public record ProductVersion {
  private const string BuildSeparator = "-";
  private const string CommitShaSeparator = "+";

  public string Release { get; init; } = "";
  public string Build { get; init; } = "";

  public string CommitSha { get; init; } = "";

  public override string ToString() {
    if (Build.Length > 0 && CommitSha.Length > 0) {
      return $"{Release}{BuildSeparator}{Build}{CommitShaSeparator}{CommitSha}";
    }

    if (Build.Length > 0) {
      return $"{Release}{BuildSeparator}{Build}";
    }

    return Release;
  }

  public static ProductVersion? GetFromAssemblyInformationOf<T>() => GetFromAssemblyInformation(typeof(T).Assembly);

  public static ProductVersion? GetFromAssemblyInformation(Assembly assembly) {
    // assumes SourceLink used to add commit SHA to assembly info
    string? assemblyInfoVs =
      assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion;
    return string.IsNullOrWhiteSpace(assemblyInfoVs) ? null : Parse(assemblyInfoVs);
  }

  public static ProductVersion Parse(string version, ProductVersionParseOptions? options = null) {
    options ??= ProductVersionParseOptions.Default;

    if (string.IsNullOrWhiteSpace(version))
      throw new ArgumentException("Value cannot be null or whitespace.", nameof(version));

    var segments = version.Split('.', StringSplitOptions.RemoveEmptyEntries);

    if (segments.Length < 4) {
      var (rawRelease, commit) = version.PartitionOnLast(CommitShaSeparator) ?? (version, "");
      return new ProductVersion {
        Release = ParseRelease(rawRelease), Build = "0", CommitSha = ShortenSha(commit, options.ShortCommitSha)
      };
    } else {
      var (rawRelease, rawBuildAndCommit) = version.PartitionOnLast(".") ?? (version, "");
      var (build, commit) = rawBuildAndCommit.PartitionOnLast(CommitShaSeparator) ?? (rawBuildAndCommit, "");

      return new ProductVersion {
        Release = ParseRelease(rawRelease), Build = build, CommitSha = ShortenSha(commit, options.ShortCommitSha)
      };
    }
  }

  private static string ShortenSha(string rawValue, bool shortenSha) {
    if (!shortenSha || rawValue.Length <= 8) return rawValue;
    return rawValue[..8];
  }

  private static string ParseRelease(string rawValue) {
    var parts = rawValue.Split('.', StringSplitOptions.RemoveEmptyEntries);
    if (parts.Length != 3) return rawValue;

    if (int.TryParse(parts[2], out var patch) && patch == 0) {
      return $"{parts[0]}.{parts[1]}";
    }

    return rawValue;
  }
}