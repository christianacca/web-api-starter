using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using Template.Shared.Model;

namespace Template.Shared.Data.Mapping;

public class ExampleModelMap : IEntityTypeConfiguration<ExampleModel> {
  public void Configure(EntityTypeBuilder<ExampleModel> entity) {
    entity.Property(e => e.Title).HasDefaultValue("Doctor");
  }
}