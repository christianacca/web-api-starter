using Microsoft.EntityFrameworkCore.Metadata.Builders;
using Microsoft.EntityFrameworkCore.Metadata.Conventions;

namespace Template.Shared.Data.Mapping.Conventions;

public class DateTimeConvention : IModelFinalizingConvention {
  public void ProcessModelFinalizing(IConventionModelBuilder modelBuilder,
    IConventionContext<IConventionModelBuilder> context) {
    var properties = modelBuilder.Metadata.GetEntityTypes().SelectMany(entityType =>
      entityType.GetDeclaredProperties().Where(p => p.ClrType == typeof(DateTime) || p.ClrType == typeof(DateTime?)
      ));

    // Ensure datetime is always stored and read as UTC
    foreach (var property in properties) {
      property.SetValueConverter(new DateTimeKindValueConverter(DateTimeKind.Utc));
    }
  }
}