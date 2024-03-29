using System.ComponentModel.DataAnnotations;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata;
using Template.Shared.Model;

namespace Template.Shared.Data.Mapping;

public static class ModelBuilderExtensions {
  public static void ApplyDefaultConventions(this ModelBuilder modelBuilder) {
    var allProperties = modelBuilder.Model.GetEntityTypes().SelectMany(e => e.GetProperties()).ToList();

    // Ensure datetime is always stored and read as UTC
    var dateTimes = allProperties
      .HasClrType<DateTime>()
      .Union(allProperties.HasClrType<DateTime?>());
    foreach (var dateTimeProperty in dateTimes) {
      dateTimeProperty.SetValueConverter(new DateTimeKindValueConverter(DateTimeKind.Utc));
    }

    // Ensure that String properties are NOT (n)varcharmax (that would be a bad idea for db perf)
    var unassignedLengthStrings = allProperties
      .HasClrType<string>()
      .HasClrAttribute<MaxLengthAttribute>(false);
    foreach (var stringProperty in unassignedLengthStrings) {
      stringProperty.SetMaxLength(500);
    }

    // Type[] ownedOrKeylessTypes = { typeof(ServerInfo) };
    var ownedOrKeylessTypes = Enumerable.Empty<Type>();
    foreach (var entityType in modelBuilder.Model.GetEntityTypes()
               .Where(t => !ownedOrKeylessTypes.Contains(t.ClrType))) {
      // Singularize table name
      entityType.SetTableName(entityType.ClrType.Name);
      // Enable Temporal table support (a more powerful and simpler way of implementing soft deletes)
      entityType.SetIsTemporal(true);
    }
  }

  private static IEnumerable<IMutableProperty> HasClrAttribute<T>(this IEnumerable<IMutableProperty> properties,
    bool value = true) {
    return properties.Where(p =>
      p.PropertyInfo != null && p.PropertyInfo.GetCustomAttributes(typeof(T), true).Any() == value);
  }

  private static IEnumerable<IMutableProperty> HasClrType<T>(this IEnumerable<IMutableProperty> properties) {
    return properties.Where(p => p.ClrType == typeof(T));
  }
}