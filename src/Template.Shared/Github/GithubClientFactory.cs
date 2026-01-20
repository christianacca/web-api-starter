using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;
using Octokit;
using System.Reflection;
using System.Security.Cryptography;

namespace Template.Shared.Github;

public interface IGitHubClientFactory {
  Task<GitHubClient> GetOrCreateClientAsync();
}

public class GitHubClientFactory(IOptionsMonitor<GithubAppOptions> options) : IGitHubClientFactory {
  private SemaphoreSlim TokenLock { get; } = new(1, 1);
  private static TimeSpan RefreshBuffer { get; } = TimeSpan.FromMinutes(5);
  private string ProductHeaderValue { get; } = Assembly.GetExecutingAssembly().GetName().Name ?? "AzureFunctionApp";

  private GitHubClient? _singletonClient;
  private string? _cachedToken;
  private DateTimeOffset TokenExpiry { get; set; } = DateTimeOffset.MinValue + RefreshBuffer;

  public async Task<GitHubClient> GetOrCreateClientAsync() {
    if (_cachedToken == null || _singletonClient == null || DateTimeOffset.UtcNow >= TokenExpiry.Subtract(RefreshBuffer)) {
      await TokenLock.WaitAsync();
      try {
        if (_cachedToken == null || _singletonClient == null || DateTimeOffset.UtcNow >= TokenExpiry.Subtract(RefreshBuffer)) {
          _cachedToken = await CreateInstallationTokenAsync(options.CurrentValue);
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

  private async Task<string> CreateInstallationTokenAsync(GithubAppOptions appOptions) {
    var jwt = CreateJwt(appOptions.AppId, appOptions.PrivateKeyPem);
    var appClient = new GitHubClient(new ProductHeaderValue(ProductHeaderValue)) {
      Credentials = new Credentials(jwt, AuthenticationType.Bearer)
    };

    var tokenResponse = await appClient.GitHubApps.CreateInstallationToken(appOptions.InstallationId);
    TokenExpiry = tokenResponse.ExpiresAt;

    return tokenResponse.Token;
  }

  private static string CreateJwt(string appId, string privateKeyPem) {
    using var rsa = RSA.Create();
    rsa.ImportFromPem(privateKeyPem.ToCharArray());

    var now = DateTimeOffset.UtcNow.UtcDateTime;

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
