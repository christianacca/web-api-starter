using System.Collections.Concurrent;
using Azure.Identity;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace Mri.Azure.ManagedIdentity;

public class TokenServiceFactory {
  private ConcurrentDictionary<string, ITokenService> Services { get; } = new();

  private IOptionsMonitor<TokenRequestOptions> RequestOptions { get; }
  private IOptionsMonitor<DefaultAzureCredentialOptions> DefaultCredentialsOptions { get; }
  private TokenServiceSelector ServiceSelector { get; }
  private IServiceProvider ServiceProvider { get; }
  private ILogger<TokenServiceFactory> Logger { get; }

  public TokenServiceFactory(
    IOptionsMonitor<TokenRequestOptions> requestOptions,
    IOptionsMonitor<DefaultAzureCredentialOptions> defaultCredentialsOptions,
    TokenServiceSelector serviceSelector,
    IServiceProvider serviceProvider,
    ILogger<TokenServiceFactory> logger
  ) {
    RequestOptions = requestOptions;
    DefaultCredentialsOptions = defaultCredentialsOptions;
    ServiceSelector = serviceSelector;
    ServiceProvider = serviceProvider;
    Logger = logger;
  }

  private ITokenService CreateService(string optionsName) {
    var options = RequestOptions.Get(optionsName);
    var credentialOptions = options.CredentialOptions ?? DefaultCredentialsOptions.Get(Options.DefaultName);
    if (credentialOptions.ManagedIdentityClientId == string.Empty) {
      credentialOptions.ManagedIdentityClientId = null;
    }

    var tokenService = ServiceSelector(optionsName, options.Audience, credentialOptions, ServiceProvider);
    Logger.LogInformation(
      "Token service {TokenService} selected for audience {TokenAudience}; Managed Identity supplied to Token service: {ManagedIdentityClientId}", 
      tokenService.GetType(), options.Audience, credentialOptions.ManagedIdentityClientId
    );
    return tokenService;
  }

  public ITokenService Get(string? optionsName = null) {
    return Services.GetOrAdd(optionsName ?? Options.DefaultName, CreateService);
  }
}

public delegate ITokenService TokenServiceSelector(
  string serviceName, string audience,
  DefaultAzureCredentialOptions credentialOptions, IServiceProvider serviceProvider
);