using System.ComponentModel.DataAnnotations;

namespace Template.Shared.Model;

public abstract class IdentityPrincipal {
  public Guid Id { get; set; }
  
  [Required(AllowEmptyStrings = false)]
  [MaxLength(100)]
  public string Name { get; set; } = "";
}

public class UserPrincipal : IdentityPrincipal {
  public string IdentityProviderUserId { get; set; } = null!;
  public bool IsAppUser { get; set; } = true;
  public string FirstName { get; set; } = "";
  public string LastName { get; set; } = "";
  public string Email { get; set; } = "";
}

public class GroupPrincipal : IdentityPrincipal {
}

public class OrganisationPrincipal : IdentityPrincipal {
  public Guid? DefaultRoleId { get; set; }

  [MaxLength(100)]
  public string? DomainName { get; set; }
}