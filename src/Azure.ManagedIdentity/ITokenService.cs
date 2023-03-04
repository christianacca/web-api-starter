namespace Mri.Azure.ManagedIdentity;

public interface ITokenService {
  ValueTask<string> GetTokenAsync(CancellationToken cancellationToken = default);
}