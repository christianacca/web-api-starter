namespace Mri.Azure.ManagedIdentity;

public class AzureIdentityConfigurationOptions {
  /// <summary>
  /// Configure the default audience scope that the token request will use
  /// </summary>
  public string? DefaultAudience { get; set; }

  /// <summary>
  /// The configuration section that will be used to configure the a default set of credential options
  /// that will be used to request a managed identity. When not supplied, this defaults to a section
  /// named "DefaultAzureCredentials"
  /// </summary>
  /// <remarks>
  /// These credential options can be overridden for an a specific audience by registering a
  /// <see cref="TokenRequestOptions"/> using <see cref="ServiceExtensions.AddAzureManagedIdentityTokenOption(Microsoft.Extensions.DependencyInjection.IServiceCollection,string,string)"/>
  /// </remarks>
  public string? DefaultAzureCredentialsConfigurationSectionName { get; set; } = "DefaultAzureCredentials";

  /// <summary>
  /// A function delegate that will be used to create an instance of a <see cref="ITokenService"/>
  /// </summary>
  /// <remarks>
  /// If not supplied then all tokens will be retrieved using <see cref="DefaultTokenService"/>
  /// </remarks>
  public TokenServiceSelector? TokenServiceSelector { get; set; }
}