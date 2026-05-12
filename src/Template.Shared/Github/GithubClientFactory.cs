using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;
using Octokit;
using System.Reflection;
using System.Security.Cryptography;

namespace Template.Shared.Github;

public interface IGitHubClientFactory {
  Task<IGitHubClient> GetOrCreateClientAsync(CancellationToken ct = default);
}

public class GitHubClientFactory(IOptionsMonitor<GithubAppCredentialOptions> credentialOptions) : IGitHubClientFactory {
  private SemaphoreSlim TokenLock { get; } = new(1, 1);
  private static TimeSpan RefreshBuffer { get; } = TimeSpan.FromMinutes(5);
  private string ProductHeaderValue { get; } = Assembly.GetExecutingAssembly().GetName().Name ?? "AzureFunctionApp";

  private IGitHubClient? _singletonClient;
  private string? _cachedToken;
  private DateTimeOffset TokenExpiry { get; set; } = DateTimeOffset.MinValue + RefreshBuffer;

  public async Task<IGitHubClient> GetOrCreateClientAsync(CancellationToken ct = default) {
    if (_cachedToken == null || _singletonClient == null || GetUtcNow() >= TokenExpiry.Subtract(RefreshBuffer)) {
      await TokenLock.WaitAsync(ct);
      try {
        if (_cachedToken == null || _singletonClient == null || GetUtcNow() >= TokenExpiry.Subtract(RefreshBuffer)) {
          _cachedToken = await CreateInstallationTokenAsync(credentialOptions.CurrentValue);
          _singletonClient = new GitHubClient(new ProductHeaderValue(ProductHeaderValue)) {
            Credentials = new Credentials(_cachedToken)
          };
        }
      }
      finally {
        TokenLock.Release();
      }
    }

    return _singletonClient;
  }

  protected virtual DateTimeOffset GetUtcNow() => DateTimeOffset.UtcNow;

  protected virtual IGitHubClient CreateBootstrapClient(string appId, string privateKeyPem) {
    var jwt = CreateJwt(appId, privateKeyPem, GetUtcNow());
    return new GitHubClient(new ProductHeaderValue(ProductHeaderValue)) {
      Credentials = new Credentials(jwt, AuthenticationType.Bearer)
    };
  }

  private async Task<string> CreateInstallationTokenAsync(GithubAppCredentialOptions appOptions) {
    var appClient = CreateBootstrapClient(appOptions.AppId, appOptions.PrivateKeyPem);

    var tokenResponse = await appClient.GitHubApps.CreateInstallationToken(appOptions.InstallationId);
    TokenExpiry = tokenResponse.ExpiresAt;

    return tokenResponse.Token;
  }

  private static string CreateJwt(string appId, string privateKeyPem, DateTimeOffset utcNow) {
    using var rsa = RSA.Create();
    rsa.ImportFromPem(privateKeyPem.ToCharArray());

    var now = utcNow.UtcDateTime;

    var signingCredentials = new SigningCredentials(
      new RsaSecurityKey(rsa),
      SecurityAlgorithms.RsaSha256
    );

    var handler = new JsonWebTokenHandler();
    var tokenDescriptor = new SecurityTokenDescriptor {
      Issuer = appId,
      IssuedAt = now,
      // This token will remain active for only a maximum of 10 minutes
      Expires = now.AddMinutes(10),
      SigningCredentials = signingCredentials
    };

    return handler.CreateToken(tokenDescriptor);
  }
}
