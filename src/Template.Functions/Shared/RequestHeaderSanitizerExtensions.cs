using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Primitives;
using Microsoft.Net.Http.Headers;

namespace Template.Functions.Shared;

public static class RequestHeaderSanitizerExtensions {
  private static readonly Regex JwtClaimPattern =
    new(@"Bearer\s+(?<header>[^.]+)\.(?<payload>[^.]+)\.(?<signature>[^.]+)");

  public static IHeaderDictionary SanitizeJwtTokenAuthzHeader(this IHeaderDictionary headers,
    params string[] additional) {
    if (!(headers.Keys.Contains(HeaderNames.Authorization, StringComparer.OrdinalIgnoreCase) ||
          additional.Any(h => headers.Keys.Contains(h, StringComparer.OrdinalIgnoreCase)))) {
      return headers;
    }

    var sanitizedHeaders = new HeaderDictionary();
    foreach (var header in headers) {
      if (StringComparer.OrdinalIgnoreCase.Equals(header.Key, HeaderNames.Authorization) ||
          additional.Contains(header.Key, StringComparer.OrdinalIgnoreCase)) {
        var sanitizedValues = new StringValues(header.Value.Select(SanitizeJwtToken).ToArray());
        sanitizedHeaders.Add(header.Key, sanitizedValues);
      } else {
        sanitizedHeaders.Add(header.Key, header.Value);
      }
    }

    return sanitizedHeaders;
  }

  private static string? SanitizeJwtToken(string? token) {
    return token == null ? null : JwtClaimPattern.Replace(token, "Bearer REDACTED.$2.REDACTED");
  }
}