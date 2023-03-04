using Azure.Extensions.AspNetCore.Configuration.Secrets;
using Azure.Security.KeyVault.Secrets;

namespace Template.Shared.Azure.KeyVault; 

public class FilteredKeyVaultSecretManager : KeyVaultSecretManager {
  public IList<string>? Sections { get; set; }

  public override bool Load(SecretProperties properties)
    => Sections == null || Sections.Any(section => properties.Name.StartsWith($"{section}--"));
}