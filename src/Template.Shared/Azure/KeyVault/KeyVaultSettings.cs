using Azure.Identity;

namespace Template.Shared.Azure.KeyVault; 

public class KeyVaultSettings {
  /// <summary>
  /// The options determining the authentication used to authenticate to Azure keyvault
  /// </summary>
  public DefaultAzureCredentialOptions DefaultAzureCredentials { get; set; } = new();

  /// <summary>
  /// Should keyvault be added as a source of configuration. Defaults to <c>true</c> when a <see cref="KeyVaultName"/> has been supplied
  /// </summary>
  public bool IsEnabled {
    get => !KeyVaultDisabled && !string.IsNullOrEmpty(KeyVaultName);
  }

  public bool KeyVaultDisabled { get; set; }

  public string KeyVaultName { get; set; } = "";
  
  /// <summary>
  /// Gets or sets the timespan to wait between attempts at polling the Azure Key Vault for changes. <c>null</c> to disable reloading.
  /// </summary>
  public TimeSpan? KeyVaultReloadInterval { get; set; }

  /// <summary>
  /// Filter the keys to load based so that only keys belonging to specific configuration sections are loaded
  /// </summary>
  /// <remarks>
  /// <em>IMPORTANT</em>: best practice says to use a separate keyvault per application per environment. Therefore,
  /// use this section filtering with caution. For example, it's likely OK when say you have different services
  /// belong to the <em>same</em> product and you have logically divided keyvault keys for each service using a section
  /// per service
  /// </remarks>
  public IList<string>? KeyVaultSections { get; set; }
}