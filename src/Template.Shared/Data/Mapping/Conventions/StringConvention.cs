using Microsoft.EntityFrameworkCore.Metadata.Builders;
using Microsoft.EntityFrameworkCore.Metadata.Conventions;

namespace Template.Shared.Data.Mapping.Conventions;

public class StringConvention : IModelFinalizingConvention {
  public void ProcessModelFinalizing(
    IConventionModelBuilder modelBuilder,
    IConventionContext<IConventionModelBuilder> context
  ) {
    var properties = modelBuilder.Metadata.GetEntityTypes().SelectMany(entityType =>
      entityType.GetDeclaredProperties().HasClrType<string>()
    );

    // Ensure that String properties are NOT (n)varcharmax (that would be a bad idea for db perf)
    foreach (var property in properties) {
      property.Builder.HasMaxLength(500);
    }
  }
}