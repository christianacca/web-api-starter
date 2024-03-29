namespace Template.Shared.Util;

public static class StringExtensions {
  /// <summary>
  /// Splits the string into two on the first occurrence of <paramref name="fragment"/> 
  /// </summary>
  public static (string Left, string Right)? PartitionOn(
    this string toSearch, string fragment, StringComparison comparisonType = StringComparison.InvariantCultureIgnoreCase
  ) {
    if (fragment.Length == 0) return null;

    var position = toSearch.IndexOf(fragment, comparisonType);
    if (position == -1) return null;

    return (toSearch[..position], toSearch[(position + fragment.Length)..]);
  }

  /// <summary>
  /// Splits the string into two on the last occurrence of <paramref name="fragment"/> 
  /// </summary>
  public static (string Left, string Right)? PartitionOnLast(
    this string toSearch, string fragment, StringComparison comparisonType = StringComparison.InvariantCultureIgnoreCase
  ) {
    if (fragment.Length == 0) return null;

    var position = toSearch.LastIndexOf(fragment, comparisonType);
    if (position == -1) return null;

    return (toSearch[..position], toSearch[(position + fragment.Length)..]);
  }

  /// <summary>
  /// Returns the characters that fall after the first occurrence of <paramref name="fragment"/> 
  /// </summary>
  public static string SubstringAfter(
    this string toSearch, string fragment, StringComparison comparisonType = StringComparison.InvariantCultureIgnoreCase
  ) {
    if (fragment.Length == 0) return string.Empty;

    var position = toSearch.IndexOf(fragment, comparisonType);
    return position == -1 ? string.Empty : toSearch[(position + fragment.Length)..];
  }

  /// <summary>
  /// Returns the characters that fall after the last occurrence of <paramref name="fragment"/> 
  /// </summary>
  public static string SubstringAfterLast(
    this string toSearch, string fragment, StringComparison comparisonType = StringComparison.InvariantCultureIgnoreCase
  ) {
    if (fragment.Length == 0) return string.Empty;

    var position = toSearch.LastIndexOf(fragment, comparisonType);
    return position == -1 ? string.Empty : toSearch[(position + fragment.Length)..];
  }

  /// <summary>
  /// Returns the characters that fall before the first occurrence of <paramref name="fragment"/> 
  /// </summary>
  public static string SubstringBefore(
    this string toSearch, string fragment, StringComparison comparisonType = StringComparison.InvariantCultureIgnoreCase
  ) {
    if (fragment.Length == 0) return string.Empty;

    var position = toSearch.IndexOf(fragment, comparisonType);
    return position == -1 ? string.Empty : toSearch[..position];
  }

  /// <summary>
  /// Returns the characters that fall before the last occurrence of <paramref name="fragment"/> 
  /// </summary>
  public static string SubstringBeforeLast(
    this string toSearch, string fragment, StringComparison comparisonType = StringComparison.InvariantCultureIgnoreCase
  ) {
    if (fragment.Length == 0) return string.Empty;

    var position = toSearch.LastIndexOf(fragment, comparisonType);
    return position == -1 ? string.Empty : toSearch[..position];
  }
}