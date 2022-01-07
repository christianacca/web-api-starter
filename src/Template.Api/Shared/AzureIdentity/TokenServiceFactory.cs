using System.Collections.Concurrent;
using Azure.Identity;
using Microsoft.Extensions.Options;

namespace Template.Api.Shared.AzureIdentity;

public class TokenServiceFactory {
  private ConcurrentDictionary<string, ITokenService> Services { get; } = new();

  private IOptionsMonitor<TokenRequestOptions> RequestOptions { get; }
  private IOptionsMonitor<DefaultAzureCredentialOptions> DefaultCredentialsOptions { get; }
  private TokenServiceSelector ServiceSelector { get; }

  public TokenServiceFactory(IOptionsMonitor<TokenRequestOptions> requestOptions,
    IOptionsMonitor<DefaultAzureCredentialOptions> defaultCredentialsOptions, TokenServiceSelector serviceSelector) {
    RequestOptions = requestOptions;
    DefaultCredentialsOptions = defaultCredentialsOptions;
    ServiceSelector = serviceSelector;
  }

  private ITokenService CreateService(string optionsName) {
    var options = RequestOptions.Get(optionsName);
    var credentialOptions = options.CredentialOptions ?? DefaultCredentialsOptions.Get(Options.DefaultName);
    if (credentialOptions.ManagedIdentityClientId == string.Empty) {
      credentialOptions.ManagedIdentityClientId = null;
    }

    return ServiceSelector(optionsName, options.Audience, credentialOptions);
  }

  public ITokenService Get(string optionsName) {
    return Services.GetOrAdd(optionsName, CreateService);
  }
}

public delegate ITokenService TokenServiceSelector(string serviceName, string audience,
  DefaultAzureCredentialOptions credentialOptions);