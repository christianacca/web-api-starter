using System.Security.Cryptography;
using System.Text;

namespace Template.Shared.Github;

/// <summary>
/// Validates GitHub webhook signatures using HMAC-SHA256
/// </summary>
public static class GithubWebhookSignatureValidator {
  private const string Sha256Prefix = "sha256=";

  /// <summary>
  /// Validates that the GitHub webhook signature matches the expected signature for the payload
  /// </summary>
  /// <param name="payload">The raw request body as a string</param>
  /// <param name="signatureHeader">The value of the X-Hub-Signature-256 header</param>
  /// <param name="secret">The webhook secret configured in GitHub</param>
  /// <returns>True if the signature is valid, false otherwise</returns>
  public static bool IsValidSignature(string payload, string? signatureHeader, string secret) {
    if (string.IsNullOrEmpty(signatureHeader)) {
      return false;
    }

    if (!signatureHeader.StartsWith(Sha256Prefix, StringComparison.OrdinalIgnoreCase)) {
      return false;
    }

    var signature = signatureHeader[Sha256Prefix.Length..];
    var expectedSignature = ComputeSignature(payload, secret);

    return ConstantTimeEquals(signature, expectedSignature);
  }

  /// <summary>
  /// Computes the HMAC-SHA256 signature for the given payload and secret
  /// </summary>
  private static string ComputeSignature(string payload, string secret) {
    var keyBytes = Encoding.UTF8.GetBytes(secret);
    var payloadBytes = Encoding.UTF8.GetBytes(payload);

    using var hmac = new HMACSHA256(keyBytes);
    var hashBytes = hmac.ComputeHash(payloadBytes);

    return BitConverter.ToString(hashBytes).Replace("-", "").ToLowerInvariant();
  }

  /// <summary>
  /// Constant-time string comparison to prevent timing attacks
  /// </summary>
  private static bool ConstantTimeEquals(string a, string b) {
    if (a.Length != b.Length) {
      return false;
    }

    var result = 0;
    for (var i = 0; i < a.Length; i++) {
      result |= a[i] ^ b[i];
    }

    return result == 0;
  }
}
