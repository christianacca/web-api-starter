using System.ComponentModel.DataAnnotations;
using Azure.Identity;

namespace Mri.Azure.ManagedIdentity;

public class TokenRequestOptions {
  /// <summary>
  /// The resource scope of the Azure service or Azure AD application that the token is meant to be used for
  /// </summary>
  /// <remarks>
  /// <para>
  /// Examples of resource scope for an Azure service:
  /// <list type="bullet">
  /// <item>Power-bi service: https://analysis.windows.net/powerbi/api/.default</item>
  /// <item>Azure SQL: https://database.windows.net/.default</item>
  /// </list>
  /// </para>
  /// <para>
  /// The resource scope for an Azure AD application is the Application (aka client) ID of that application
  /// </para>
  /// </remarks>
  [Required, MinLength(1)]
  public string Audience { get; set; } = null!;

  /// <summary>
  /// The options that determine the credentials that will be used to make the token request
  /// </summary>
  /// <remarks>
  /// If not set then the default credentials registered for the app will be used for the request
  /// </remarks>
  public DefaultAzureCredentialOptions? CredentialOptions { get; set; }
}