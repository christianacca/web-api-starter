namespace Template.Api.Shared.AzureIdentity;

public interface ITokenService {
  ValueTask<string> GetTokenAsync(CancellationToken cancellationToken = default);
}