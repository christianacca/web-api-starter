using Microsoft.EntityFrameworkCore.Metadata.Builders;
using Microsoft.EntityFrameworkCore.Metadata.Conventions;

namespace Template.Shared.Data.Mapping.Conventions;

public class DiscriminatorPropertyConvention : IModelFinalizingConvention {
  public void ProcessModelFinalizing(
    IConventionModelBuilder modelBuilder,
    IConventionContext<IConventionModelBuilder> context
  ) {
    foreach (var entityType in modelBuilder.Metadata.GetEntityTypes()
               .Where(entityType => entityType.BaseType == null)) {
      var discriminatorProperty = entityType.FindDiscriminatorProperty();
      if (discriminatorProperty == null || discriminatorProperty.ClrType != typeof(string)) {
        continue;
      }

      var maxDiscriminatorValueLength = entityType
        .GetDerivedTypesInclusive().Select(e => e.GetDiscriminatorValue()).OfType<string>().Select(v => v.Length)
        .Max();
      discriminatorProperty.Builder.HasMaxLength(maxDiscriminatorValueLength);
      discriminatorProperty.Builder.IsUnicode(false);
    }
  }
}