using Azure.Core;
using Azure.Identity;

namespace Mri.Azure.ManagedIdentity;

public class DefaultTokenService : ITokenService {
  private TokenRequestContext Context { get; }
  private TokenCredential Credential { get; }

  public DefaultTokenService(string audience, DefaultAzureCredentialOptions credentialsOptions) {
    Credential = new DefaultAzureCredential(credentialsOptions);
    Context = new TokenRequestContext(new[] { audience });
  }

  public virtual async ValueTask<string> GetTokenAsync(CancellationToken cancellationToken = default) {
    var result = await Credential.GetTokenAsync(Context, cancellationToken);
    return result.Token;
  }
}