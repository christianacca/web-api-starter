using Azure.Identity;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Options;

namespace Mri.Azure.ManagedIdentity;

public static class ServiceExtensions {
  private static readonly TokenServiceSelector DefaultTokenServiceSelector = (_, audience, credentialOptions, _) =>
    new DefaultTokenService(audience, credentialOptions);

  /// <summary>
  /// Add a Token request option
  /// </summary>
  /// <remarks>
  /// Use this method where you have multiple audiences that your app targets
  /// </remarks>
  public static IServiceCollection AddAzureManagedIdentityTokenOption(this IServiceCollection services,
    string optionsName,
    string configurationSection) {
    services
      .AddOptions<TokenRequestOptions>(optionsName)
      .BindConfiguration(configurationSection)
      .ValidateDataAnnotations();
    return services;
  }

  /// <summary>
  /// Add a Token request option
  /// </summary>
  /// <remarks>
  /// Use this method where you have multiple audiences that your app targets
  /// </remarks>
  public static IServiceCollection AddAzureManagedIdentityTokenOption(this IServiceCollection services,
    string optionsName,
    Action<TokenRequestOptions> configuration) {
    services
      .AddOptions<TokenRequestOptions>(optionsName)
      .Configure(configuration)
      .ValidateDataAnnotations();
    return services;
  }

  /// <summary>
  /// Add Azure support for azure managed identity tokens, using default configuration options
  /// </summary>
  /// <example>
  /// <code>
  /// services.AddAzureManagedIdentityToken("https://analysis.windows.net/powerbi/api/.default")
  /// </code>
  /// </example>
  public static IServiceCollection AddAzureManagedIdentityToken(this IServiceCollection services, string audience) {
    return AddAzureManagedIdentityToken(services, options => { options.DefaultAudience = audience; });
  }

  /// <summary>
  /// Add Azure support for azure managed identity tokens using the configuration supplied
  /// </summary>
  /// <example>
  /// <code>
  /// services.AddAzureManagedIdentityToken(options => {
  ///   options.TokenServiceSelector = (optionsName, audience, credentialOptions, sp) => {
  ///     return optionsName switch {
  ///       "Functions" when environment.IsDevelopment() => new FakeTokenService(),
  ///       "PowerBi" when environment.IsDevelopment() => ActivatorUtilities.CreateInstance&lt;MyCustomTokenService>(sp),
  ///       "PowerBi" => new CachedTokenService(audience, credentialOptions),
  ///       _ => new CachedTokenService(audience, credentialOptions)
  ///     };
  ///   };
  ///   options.DefaultAzureCredentialsConfigurationSectionName = "Api:DefaultAzureCredentials";
  /// })
  /// </code>
  /// </example>
  public static IServiceCollection AddAzureManagedIdentityToken(this IServiceCollection services,
    Action<AzureIdentityConfigurationOptions> configOptions) {
    var options = new AzureIdentityConfigurationOptions();
    configOptions(options);

    services.AddSingleton<TokenServiceFactory>();
    if (options.TokenServiceSelector != null) {
      services.AddSingleton(_ => options.TokenServiceSelector);
    } else {
      services.TryAddSingleton(_ => DefaultTokenServiceSelector);
    }

    if (!string.IsNullOrEmpty(options.DefaultAzureCredentialsConfigurationSectionName)) {
      services.AddOptions<DefaultAzureCredentialOptions>()
        .BindConfiguration(options.DefaultAzureCredentialsConfigurationSectionName);
    }

    if (!string.IsNullOrEmpty(options.DefaultAudience)) {
      services.AddAzureManagedIdentityTokenOption(Options.DefaultName,
        tokenOptions => { tokenOptions.Audience = options.DefaultAudience; });
    }

    return services;
  }
}