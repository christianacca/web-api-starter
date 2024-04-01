using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using Template.Shared.Model;

namespace Template.Shared.Data.Mapping;

public class IdentityPrincipalMap : IEntityTypeConfiguration<IdentityPrincipal> {
  public void Configure(EntityTypeBuilder<IdentityPrincipal> entity) {
    entity.ToTable(nameof(IdentityPrincipal));
  }
}