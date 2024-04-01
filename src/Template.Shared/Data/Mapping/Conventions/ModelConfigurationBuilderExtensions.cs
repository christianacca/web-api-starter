using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata;
using Microsoft.EntityFrameworkCore.Metadata.Conventions;

namespace Template.Shared.Data.Mapping.Conventions;

public static class ModelConfigurationBuilderExtensions {
  public static void ApplyDefaultConventions(this ModelConfigurationBuilder configurationBuilder) {
    configurationBuilder.Conventions.Remove(typeof(TableNameFromDbSetConvention));
    configurationBuilder.Conventions.Add(_ => new TemporalTableConvention());
    configurationBuilder.Conventions.Add(_ => new StringConvention());
    configurationBuilder.Conventions.Add(_ => new DateTimeConvention());
    // important: this convention must be added after the StringConvention
    configurationBuilder.Conventions.Add(_ => new DiscriminatorPropertyConvention());
  }


  public static IEnumerable<IConventionProperty> HasClrType<T>(this IEnumerable<IConventionProperty> properties) {
    return properties.Where(p => p.ClrType == typeof(T));
  }
}